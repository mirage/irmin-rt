open Lwt
open Irmin_unix

module Store = Irmin.Basic (Irmin_git.FS) (Irmin.Contents.String)
module View = Irmin.View(Store)

exception InvalidCommand

(* assume the keys are sequential *)
let get_cnt store =
  Store.list (store "") ["root"] >>= fun l ->
  let cnt = (List.fold_left (fun acc i ->
    let i = int_of_string (List.nth i 1) in
    if i > acc then
      i
    else
      acc
  ) 0 l) in
  return cnt

let usage () =
  Printf.printf "usage: search [-samples num] -repo path\n%!"

let rec args i samples repo =
  if i >= Array.length Sys.argv then
    (samples,repo)
  else
    match Sys.argv.(i) with
    | "-samples" -> args (i+2) (Some (int_of_string Sys.argv.(i+1))) repo
    | "-repo" -> args (i+2) samples (Some Sys.argv.(i+1))
    | _ -> raise InvalidCommand

module Option = struct
  let value_exn = function None -> raise Not_found | Some x -> x
  let value ~default = function None -> default | Some x -> x
end

let commands f =
  try
    let (samples,repo) = args 1 None None in
    f (Option.value samples ~default:1000) (Option.value_exn repo)
  with InvalidCommand -> usage (); return ()

let () =
  Lwt_main.run (
    commands (fun samples repo ->
    let config = Irmin_git.config ~root:repo ~bare:true () in
    Store.create config task >>= fun store ->
    get_cnt store >>= fun cnt ->
    let rec search i avg =
      if i > samples then
        return avg
      else (
        let key = string_of_int ((mod) (Random.int 999999999) (cnt+1)) in
        let tm = Unix.gettimeofday () in
        Store.read_exn (store "") ["root";key] >>= fun v ->
        let tm1 = Unix.gettimeofday () in
        let diff = tm1 -. tm in
        search (i + 1) (avg +. diff)
      )
    in
    let tm = Unix.gettimeofday () in
    search 1 0. >>= fun avg ->
    let tm1 = Unix.gettimeofday () in
    Printf.printf "%d random accesses with avg: %0.4fsec, total: %0.4fsec\n%!" samples (avg /. (float_of_int samples)) (tm1 -. tm);
    return ()
    )
  )
