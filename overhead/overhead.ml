open Lwt
open Irmin_unix

module Store = Irmin.Basic (Irmin_git.FS) (Irmin.Contents.String)
module View = Irmin.View(Store)

let _bytes = ref ""

let unique_ascii_content ?(size=1_000_000) () =
  return (Bytes.init size (fun _ ->
    let i = (mod) (Random.int 999999999) 128 in
    let i = if i < 32 then i + 32 else i in
    (char_of_int (i))))

let ascii_content ?(size=1_000_000) () =
  if !_bytes <> "" then
    return !_bytes
  else (
    _bytes := Bytes.init size (fun _ -> '0');
    return !_bytes
  )

let get_image img =
  Lwt_unix.openfile img [Lwt_unix.O_RDONLY] 0o666 >>= fun fd ->
  let ch = Lwt_io.of_fd ~mode:Lwt_io.Input fd in
  Lwt_io.read ch >>= fun bytes ->
  Lwt_io.close ch >>= fun () ->
  return bytes

let image_content img =
  if !_bytes <> "" then
    return !_bytes
  else (
    get_image img >>= fun bytes ->
    _bytes := bytes;
    return !_bytes
  )

let unique_image_content img cnt =
  image_content img >>= fun bytes ->
  let key = Printf.sprintf "%07d" cnt in
  let bytes = Bytes.cat bytes key in
  Bytes.blit key 0 bytes 0 7;
  return bytes

exception InvalidCommand

let get_content content key =
  match content with
  | `Ascii size -> ascii_content ~size ()
  | `AsciiU size -> unique_ascii_content ~size ()
  | `Image path -> image_content path
  | `ImageU path -> unique_image_content path key

(*
 * -ascii[-u] size (size of text)
 * -image[-u] path (image's path)
 * -cnt messages (number of messages)
 *)
let rec args i content start cnt group once repo repeat =
  if i >= Array.length Sys.argv then
    (content,start,cnt,group,once,repo,repeat)
  else
    match Sys.argv.(i) with
    | "-ascii" -> args (i+2) (Some (`Ascii (int_of_string Sys.argv.(i+1)))) start cnt group once repo repeat
    | "-ascii-u" -> args (i+2) (Some (`AsciiU (int_of_string Sys.argv.(i+1)))) start cnt group once repo repeat
    | "-image" -> args (i+2) (Some (`Image Sys.argv.(i+1))) start cnt group once repo repeat
    | "-image-u" -> args (i+2) (Some (`ImageU Sys.argv.(i+1))) start cnt group once repo repeat
    | "-start" -> args (i+2) content (Some (int_of_string Sys.argv.(i+1))) cnt group once repo repeat
    | "-cnt" -> args (i+2) content start (Some (int_of_string Sys.argv.(i+1))) group once repo repeat
    | "-group" -> args (i+2) content start cnt (Some (int_of_string Sys.argv.(i+1))) once repo repeat
    | "-commit-once" -> args (i+1) content start cnt group true repo repeat
    | "-repo" -> args (i+2) content start cnt group once (Some Sys.argv.(i+1)) repeat
    | "-repeat" -> args (i+2) content start cnt group once repo (int_of_string Sys.argv.(i+1))
    | _ -> raise InvalidCommand

let usage () =
  Printf.printf "usage: overhead [-ascii[-u] size|-image[-u] path] -cnt num
  -repo path [-start num] [-group num] [-commit-once] [-repeat number]\n%!"

module Option = struct
  let value_exn = function None -> raise Not_found | Some x -> x
  let value ~default = function None -> default | Some x -> x
end

let commands f =
  try
    let (content,start,cnt,group,once,repo,repeat) = args 1 None None None None false None 1 in
    if content = None || cnt = None || repo = None then (
      usage ();
      return ()
    ) else
      f (Option.value_exn content) (Option.value start ~default:0)
        (Option.value_exn cnt) group once (Option.value_exn repo) repeat
  with InvalidCommand -> usage (); return ()

let pr store key =
  Store.read_exn (store "reading store") ["root"; string_of_int key] >>= fun v ->
  Printf.printf "value at key %d %s\n%!" key v;
  return ()

let get_key start i = function
  | None -> 
    let key = string_of_int (start + i) in
    ([key], key)
  | Some group -> 
    let key1 = string_of_int ((start + i) / group) in
    let key2 = string_of_int ((mod) (start + i) group) in
    ([key1;key2], key1 ^ ":" ^ key2)

let du path =
  let ci = Unix.open_process_in ("du -csh " ^ path) in
  let str = Pervasives.input_line ci in
  let _ = Unix.close_process_in ci in
  let re = Re_posix.compile_pat "(^[\t ]*[0-9.]+)([KMG])" in
  let s = Re.exec re str in
  let size = float_of_string (Re.get s 1) in
  int_of_float (
    match (Re.get s 2) with
    | "K" -> size
    | "M" -> size *. 1000.
    | "G" -> size *. 1000000.
    | _ -> assert (false)
  )

let fs path =
  let ci = Unix.open_process_in ("cd " ^ path ^ ";git reset master --hard") in
  let rec readon () =
    try
      let _ = Pervasives.input_line ci in
      readon ()
    with End_of_file -> ()
  in
  readon ();
  let root = Filename.concat path "root" in
  let _ = Unix.close_process_in ci in
  let size = du root in
  let _ = Unix.system ("cd " ^ path ^ ";rm -rf " ^ root) in
  size

let () =
  Lwt_main.run (
    commands (fun content start cnt group once repo repeat ->
    let config = Irmin_git.config ~root:repo ~bare:true () in
    Store.create config task >>= fun store ->
    let rec repeat_times start n =
      begin
        if once then
          View.of_path (store "view of path") ["root"] >>= fun view -> return (Some view)
        else
          return None
      end >>= fun gview ->
      let rec fill i origsize =
        if i > cnt then
          return origsize
        else (
          begin 
            match gview with
            | Some view -> return view
            | None -> View.of_path (store "view of path") ["root"] 
          end >>= fun view ->
          get_content content (start+i) >>= fun bytes ->
          let (key,str) = get_key start i group in
          let len = Bytes.length bytes in
          let origsize = origsize + len in
          View.update view key bytes >>= fun () ->
          begin
            match gview with
            | Some _ -> return ()
            | None -> View.update_path (store "updating store") ["root"] view 
          end >>= fun () ->
          fill (i + 1) origsize
        )
      in
      fill 1 0 >>= fun origsize ->
      begin
      match gview with
      | Some view -> View.update_path (store "updating store") ["root"] view
      | None -> return ()
      end >>= fun () ->
      let size = du (Filename.concat repo  ".git") in
      let size_fs = fs repo in
      Printf.printf "%d,%d,%d,%d\n" (cnt*n) ((origsize*n)/1000) size size_fs;
      if n = repeat then
        return ()
      else
        repeat_times (n * cnt) (n + 1) 
    in
    repeat_times start 1
    )
  )
