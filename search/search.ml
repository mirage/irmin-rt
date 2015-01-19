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
  Printf.printf "max key is %d\n%!" cnt;
  return cnt

let usage () =
  Printf.printf "usage: search [-samples num]\n%!"

let rec args i samples =
  if i >= Array.length Sys.argv then
    (samples)
  else
    match Sys.argv.(i) with
    | "-samples" -> args (i+2) (Some (int_of_string Sys.argv.(i+1)))
    | _ -> raise InvalidCommand

module Option = struct
  let value ~default = function None -> default | Some x -> x
end

let commands f =
  try
    let (samples) = args 1 None in
    f (Option.value samples ~default:1000)
  with InvalidCommand -> usage (); return ()

let () =
  Lwt_main.run (
    commands (fun samples ->
    let config = Irmin_git.config ~root:"/tmp/irmin/test" ~bare:true () in
    Store.create config task >>= fun store ->
    get_cnt store >>= fun cnt ->
    let rec search i =
      if i > samples then
        return ()
      else (
        let key = string_of_int ((mod) (Random.int 999999999) (cnt+1)) in
        let tm = Unix.gettimeofday () in
        Store.read_exn (store "") ["root";key] >>= fun v ->
        let tm1 = Unix.gettimeofday () in
        Printf.printf "%s %0.4f\n%!" key (tm1 -. tm);
        search (i + 1)
      )
    in
    search 1
    )
  )
