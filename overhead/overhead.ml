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
let rec args i content start cnt =
  if i >= Array.length Sys.argv then
    (content,start,cnt)
  else
    match Sys.argv.(i) with
    | "-ascii" -> args (i+2) (Some (`Ascii (int_of_string Sys.argv.(i+1)))) start cnt
    | "-ascii-u" -> args (i+2) (Some (`AsciiU (int_of_string Sys.argv.(i+1)))) start cnt
    | "-image" -> args (i+2) (Some (`Image Sys.argv.(i+1))) start cnt
    | "-image-u" -> args (i+2) (Some (`ImageU Sys.argv.(i+1))) start cnt
    | "-start" -> args (i+2) content (Some (int_of_string Sys.argv.(i+1))) cnt
    | "-cnt" -> args (i+2) content start (Some (int_of_string Sys.argv.(i+1)))
    | _ -> raise InvalidCommand

let usage () =
  Printf.printf "usage: overhead [-ascii[-u] size|-image[-u] path] -cnt num -start num\n%!"

module Option = struct
  let value_exn = function None -> raise Not_found | Some x -> x
  let value ~default = function None -> default | Some x -> x
end

let commands f =
  try
    let (content,start,cnt) = args 1 None None None in
    if content = None || cnt = None then (
      usage ();
      return ()
    ) else
      f (Option.value_exn content) (Option.value start ~default:0)
        (Option.value_exn cnt)
  with InvalidCommand -> usage (); return ()

let pr store key =
  Store.read_exn (store "") ["root"; string_of_int key] >>= fun v ->
  Printf.printf "value at key %d %s\n%!" key v;
  return ()

let () =
  Lwt_main.run (
    commands (fun content start cnt ->
    let config = Irmin_git.config ~root:"/tmp/irmin/test" ~bare:true () in
    Store.create config task >>= fun store ->
    let rec fill i =
      if i > cnt then
        return ()
      else (
        View.of_path task (store "") ["root"] >>= fun view ->
        get_content content (start+i) >>= fun bytes ->
        Printf.printf "%07d %d\n%!" (start+i) (Bytes.length bytes);
        View.update (view "") [string_of_int i] bytes >>= fun () ->
        View.update_path "" store ["root"] view >>= fun () ->
        fill (i + 1)
      )
    in
    fill 1
    )
  )
