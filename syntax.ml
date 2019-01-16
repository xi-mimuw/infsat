(** Syntax for unprocessed terms created by the parser *)

type atom = Name of string | NT of string
and preterm = PApp of atom * preterm list
type prerule = string * string list * preterm
type prerules = prerule list

type preformula = FConst of string 
                | FVar of int * string 
                | FAnd of preformula * preformula
                | FOr of preformula * preformula
type ata_trans = (string * string) * preformula

type preterminal = PTerminal of string * int * bool
type preterminals = preterminal list

let rec string_of_vars vl =
  match vl with
  | [] -> ""
  | v::vl' -> v^" "^(string_of_vars vl')

let rec string_of_atom h =
  match h with
  | Name(s) -> s
  | NT(s) -> s
and string_of_preterm pterm =
  match pterm with
  | PApp(h, pterms) -> (string_of_atom h)^" "^(string_of_preterms pterms)
and string_of_preterms pterms =
  match pterms with
  | [] -> ""
  | pt::pterms' ->
    match pt with
    | PApp(_,[]) -> (string_of_preterm pt)^" "^(string_of_preterms pterms')
    | _ -> "("^(string_of_preterm pt)^") "^(string_of_preterms pterms')

let string_of_prerule (f, vl, pterm) =
   f^" "^(string_of_vars vl)^" -> "^(string_of_preterm pterm)

let rec string_of_prerules_aux prerules =
  match prerules with
    [] -> ""
  | prule::prerules' ->
     (string_of_prerule prule)^".\n"^(string_of_prerules_aux prerules')

let string_of_prerules prerules =
  "%BEGING\n"^(string_of_prerules_aux prerules)^"%ENDG\n"

let string_of_preterminal pt =
  match pt with
  | PTerminal(name, arity, counted) ->
    let string_of_counted =
      match counted with
      | true -> " counted"
      | false -> ""
    in
    name^" -> "^(string_of_int arity)^string_of_counted

let rec string_of_preterminals pts =
  match pts with
  | [] -> ""
  | pt::pts' -> string_of_preterminal pt^".\n"^(string_of_preterminals pts')

let rec string_of_states qs =
  match qs with
    [] -> ""
  | q::qs' -> q^" "^(string_of_states qs')

let string_of_transition ((q,a), qs) =
  q^" "^a^" -> "^(string_of_states qs)

let rec string_of_transitions_aux trs =
  match trs with
   [] -> ""
 | tr::trs' ->
     (string_of_transition tr)^".\n"^(string_of_transitions_aux trs')

let string_of_transitions trs = 
  "%BEGINA\n"^(string_of_transitions_aux trs)^"%ENDA\n";;

let ntid = ref 0
let new_ntname() =
   let x = !ntid in
   let _ = (ntid := !ntid + 1) in
     ("$FUN"^(string_of_int x))
