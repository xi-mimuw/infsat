open GrammarCommon
open HGrammar
open Type

type nt_ty = nt_id * ty

let nt_ty_compare : nt_ty -> nt_ty -> int =
  Utilities.compare_pair Pervasives.compare Ty.compare

let nt_ty_eq (nt1, ty1 : nt_ty) (nt2, ty2 : nt_ty) : bool =
  nt1 = nt2 && Ty.equal ty1 ty2

let string_of_nt_ty (nt, ty : nt_ty) : string =
  string_of_int nt ^ " : " ^ string_of_ty ty

module NTTyMap = struct
  include Map.Make (struct
      type t = nt_id * ty
      let compare = nt_ty_compare
    end)

  let of_list (l : (key * 'a) list) : 'a t = of_seq @@ List.to_seq l
end

module NTTySet = struct
  include Set.Make (struct
      type t = nt_ty
      let compare = nt_ty_compare
    end)

  let set_of_map_keys (m : 'a NTTyMap.t) : t =
    of_seq @@ Seq.map fst @@ NTTyMap.to_seq m
end

type t_ty = terminal * ty

let string_of_t_ty (t, ty : t_ty) : string =
  string_of_terminal t ^ " : " ^ string_of_ty ty

module TTyMap =
  Map.Make (struct
    type t = t_ty
    let compare = Utilities.compare_pair Pervasives.compare Ty.compare
  end)

module HlocMap = struct
  include Map.Make (struct
      type t = hloc
      let compare = Pervasives.compare
    end)

  let string_of_int_binding (loc, count : hloc * int) : string =
    let count_info =
      if count = 1 then
        ""
      else
        " (x" ^ string_of_int count ^ ")"
    in
    string_of_int loc ^ count_info

  let sum (m : int t) : int =
    fold (fun _ count acc -> count + acc) m 0

  (** Comparison between two integer hloc maps where two maps are the same iff their sums are both
      zero, both one, or both at least two. *)
  let multi_compare (m1 : int t) (m2 : int t) : int =
    Pervasives.compare (min (sum m1) 2) (min (sum m2) 2)

  let sum_union : int t -> int t -> int t =
    union (fun _ count1 count2 -> Some (count1 + count2))
end
