open GrammarCommon
open HGrammar
open Type
open TypingCommon
open Utilities

type bix = int
module BixMap = IntMap
module BixSet = IntSet
module HtermsMap = IntMap

(** Compressed collection of possible types of variables and nonterminals. Its two main features
    are keeping possible typings of hterms in the form of a product instead of product's elements
    as long as possible and imposing a restriction that given typing of a nonterminal or hterms
    has to be used at least once in a short-circuit-friendly way. *)
type ctx = {
  (** Mapping from variable positions (i.e., without nonterminal) to position of hterms they're in
      in the processed binding (binding index) and position of variable in these hterms. *)
  var_bix : (bix * int) IntMap.t;
  (** Mapping from binding index to possible htys for the hterms represented by it. *)
  bix_htys : HtySet.t BixMap.t;
  (** Optional restriction that one of hterms with bix from given set must have types hty.
      It is assumed (and not checked) that hterms with bix from that set have possible types hty
      in bix_htys. If this map is empty then it means that the restriction can't be satisfied
      and this context is empty. This is map instead of a set plus common type because of
      possible mask applied to variable types. *)
  forced_hterms_hty : hty BixMap.t option;
  (** Optional restriction that one of nonterminals in given locations needs to have type ty.
      It is assumed (and not checked) that nonterminals in these locations have possible type
      ty in nt_ity supplied to operations working on nonterminals. If this set is empty then
      it means that the restriction can't be satisfied and this context is empty. *)
  forced_nt_ty : (HlocSet.t * TySet.t) option
}

(** Normalize the context, i.e., remove non-forced typings for given binding index (bix) if it
    is the last one with possible forced typing. There is no need for such cleanup in the case of
    nonterminals, since these are processed by location and each location is processed at most
    once. *)
let ctx_normalize (ctx : ctx) : ctx =
  match ctx.forced_hterms_hty with
  | Some fbix_htys ->
    if BixMap.is_singleton fbix_htys then
      let bix, hty = BixMap.choose fbix_htys in
      assert (HtySet.mem hty @@ BixMap.find bix ctx.bix_htys);
      let bix_htys = BixMap.add bix (HtySet.singleton hty) ctx.bix_htys in
      (* the requirement was satisfied *)
      { ctx with bix_htys = bix_htys; forced_hterms_hty = None }
    else
      ctx
  | None -> ctx

let mk_ctx (var_bix : (bix * int) IntMap.t) (bix_htys : HtySet.t BixMap.t)
    (forced_hterms_hty : hty BixMap.t option)
    (forced_nt_ty : (hloc list * TySet.t) option) : ctx =
  let ctx = {
    var_bix = var_bix;
    bix_htys = bix_htys;
    forced_hterms_hty = forced_hterms_hty;
    forced_nt_ty = option_map (fun (flocs, ftys) ->
        (HlocSet.of_list flocs, ftys)
      ) forced_nt_ty
  } in
  ctx_normalize ctx

(** The number of different var typings possible to generate in the current environment. *)
let ctx_var_combinations (ctx : ctx) : int =
  match ctx.forced_hterms_hty with
  | None ->
    IntMap.fold (fun _ htys acc -> acc * (HtySet.cardinal htys)) ctx.bix_htys 1
  | Some fbix_htys ->
    let non_forced_cat_comb, forced_mul, forced_wrong_mul =
      IntMap.fold (fun bix htys (nfc, fc, fcw) ->
          let s = HtySet.cardinal htys in
          match BixMap.find_opt bix fbix_htys with
          | Some hty ->
            assert (HtySet.mem hty htys);
            (nfc, fc * s, fcw * (s - 1))
          | None ->
            (nfc * s, fc, fcw)
        ) ctx.bix_htys (1, 1, 1)
    in
    non_forced_cat_comb * (forced_mul - forced_wrong_mul)

(** Decreases ctx.bix_htys to its subset htys. *)
let ctx_shrink_htys (ctx : ctx) (bix : bix) (htys : HtySet.t) : ctx option =
  if HtySet.is_empty htys then
    None
  else
    let bix_htys = IntMap.add bix htys ctx.bix_htys in
    match ctx.forced_hterms_hty with
    | None ->
      Some { ctx with bix_htys = bix_htys }
    | Some fbix_htys ->
      match BixMap.find_opt bix fbix_htys with
      | Some hty ->
        if not @@ HtySet.mem hty htys then
          if BixMap.is_singleton fbix_htys then
            (* requirement can't be satisfied for this bix anymore and it was the last bix *)
            None
          else
            let fbix_htys = BixMap.remove bix fbix_htys in
            (* requirement can't be satisfied, but there are more bixs *)
            let ctx = { ctx with bix_htys = bix_htys; forced_hterms_hty = Some fbix_htys } in
            Some (ctx_normalize ctx)
        else if HtySet.cardinal htys = 1 then
          (* requirement was satisfied *)
          Some { ctx with bix_htys = bix_htys; forced_hterms_hty = None }
        else
          (* requirement can still be satisfied, but there are less hty options now *)
          Some { ctx with bix_htys = bix_htys }
      | None ->
        Some { ctx with bix_htys = bix_htys }

(** Create one compressed product like this for each combination of possible within
    the context restrictions type of variable v and each context resulting from this. *)
let ctx_split_var (ctx : ctx) (_, v : var_id) : (ty * ctx) list =
  let bix, i = IntMap.find v ctx.var_bix in
  let htys = IntMap.find bix ctx.bix_htys in
  (* splitting htys by type of i-th variable in them *)
  let ty_htys : HtySet.t TyMap.t =
    HtySet.fold (fun hty acc ->
        let ity = hty.(i) in
        TySet.fold (fun ty acc ->
            let htys =
              match TyMap.find_opt ty acc with
              | Some htys -> HtySet.add hty htys
              | None -> HtySet.singleton hty
            in
            TyMap.add ty htys acc
          ) ity acc
      ) htys TyMap.empty
  in
  TyMap.fold (fun ty htys acc ->
      match ctx_shrink_htys ctx bix htys with
      | Some ctx -> (ty, ctx) :: acc
      | None -> acc
    ) ty_htys []

(** Create a new compressed product like this, but where variable v is of type ty.
    If variable v is not on the list, unchanged context with this variable is returned. *)
let ctx_enforce_var (ctx : ctx) (_, v : var_id) (ty : ty) : (ty * ctx) option =
  match IntMap.find_opt v ctx.var_bix with
  | Some (bix, i) ->
    let htys = IntMap.find bix ctx.bix_htys in
    let htys =
      HtySet.filter (fun hty ->
          TySet.mem ty hty.(i)
        ) htys
    in
    option_map (fun ctx -> (ty, ctx)) @@ ctx_shrink_htys ctx bix htys
  | None ->
    Some (ty, ctx)

let ctx_split_nt (ctx : ctx) (nt_ity : TySet.t array) (nt : nt_id) (loc : hloc) : (ty * ctx) list =
  match ctx.forced_nt_ty with
  | Some (flocs, ftys) ->
    if HlocSet.mem loc flocs then
      TySet.fold (fun ty acc ->
          if TySet.mem ty ftys then
            (* requirement was satisfied *)
            (ty, { ctx with forced_nt_ty = None }) :: acc
          else
            let flocs = HlocSet.remove loc flocs in
            if HlocSet.is_empty flocs then
              (* requirement was not satisfied and it was the last chance *)
              acc
            else
              (* requirement was not satisfied, but there are more options *)
              (ty, { ctx with forced_nt_ty = Some (flocs, ftys) }) :: acc
        ) nt_ity.(nt) []
    else
      List.map (fun ty -> (ty, ctx)) @@ TySet.elements nt_ity.(nt)
  | None ->
    List.map (fun ty -> (ty, ctx)) @@ TySet.elements nt_ity.(nt)

let ctx_enforce_nt (ctx : ctx) (nt_ity : TySet.t array) (nt : nt_id) (loc : hloc)
    (ty : ty) : (ty * ctx) option =
  if TySet.mem ty nt_ity.(nt) then
    match ctx.forced_nt_ty with
    | Some (flocs, ftys) ->
      if HlocSet.mem loc flocs then
        if TySet.mem ty ftys then
          (* requirement was satisfied *)
          Some (ty, { ctx with forced_nt_ty = None })
        else
          let flocs = HlocSet.remove loc flocs in
          if HlocSet.is_empty flocs then
            (* requirement was not satisfied and it was the last position *)
            None
          else
            (* requirement was not satisfied, but there are more positions *)          
            Some (ty, { ctx with forced_nt_ty = Some (flocs, ftys) })
      else
        Some (ty, ctx)
    | None ->
      Some (ty, ctx)
  else
    None

exception EmptyIntersection

let intersect_ctxs (ctx1 : ctx) (ctx2 : ctx) : ctx option =
  try
    let bix_htys =
      BixMap.merge (fun _ htys1 htys2 ->
          match htys1, htys2 with
          | None, _ | _, None -> failwith "Context keys differ."
          | Some htys1, Some htys2 ->
            let htys = HtySet.inter htys1 htys2 in
            (* If it becomes empty due to intersection but wasn't empty before,
               there are conflicting assumptions. *)
            if HtySet.is_empty htys && not (HtySet.is_empty htys1 && HtySet.is_empty htys2) then
              raise EmptyIntersection
            else
              Some htys
        ) ctx1.bix_htys ctx2.bix_htys
    in
    let forced_hterms_hty =
      match ctx1.forced_hterms_hty, ctx2.forced_hterms_hty with
      | None, _ | _, None -> None
      | Some fbix_htys1, Some fbix_htys2 ->
        let fbix_htys = BixMap.merge (fun _ h1 h2 ->
            match h1, h2 with
            | Some _, Some _ -> h1
            | _, _ -> None
          ) fbix_htys1 fbix_htys2
        in
        if BixMap.is_empty fbix_htys then
          raise_notrace EmptyIntersection
        else if fbix_htys |> BixMap.exists (fun bix _ ->
            HtySet.is_singleton @@ BixMap.find bix bix_htys) then
          (* Due to intersection, the requirement was satisfied. *)
          None
        else
          Some fbix_htys
    in
    let forced_nt_ty =
      match ctx1.forced_nt_ty, ctx2.forced_nt_ty with
      | None, _ | _, None -> None
      | Some (flocs1, fty), Some (flocs2, _) ->
        let flocs = HlocSet.inter flocs1 flocs2 in
        if HlocSet.is_empty flocs then
          raise_notrace EmptyIntersection
        else
          Some (flocs, fty)
    in
    let ctx = {
      var_bix = ctx1.var_bix;
      bix_htys = bix_htys;
      forced_hterms_hty = forced_hterms_hty;
      forced_nt_ty = forced_nt_ty
    } in
    Some (ctx_normalize ctx)
  with
  | EmptyIntersection -> None

let ctx_requirements_satisfied ctx : bool =
  ctx.forced_hterms_hty = None && ctx.forced_nt_ty = None

(** Compares two product environments. Only takes the mutable bix_hty and set in
    forced_nt_ty into account. forced_hterms_hty could be computed from common ancestor
    one and bix_htys. *)
let ctx_compare (ctx1 : ctx) (ctx2 : ctx) : int =
  compare_pair
    (BixMap.compare HtySet.compare)
    (option_compare HlocSet.compare)
    (ctx1.bix_htys, option_map fst ctx1.forced_nt_ty)
    (ctx2.bix_htys, option_map fst ctx2.forced_nt_ty)

(** Equality that also takes var_bix and forced_hterms_hty into account. For testing purposes. *)
let ctx_equal (ctx1 : ctx) (ctx2 : ctx) : bool =
  ctx_compare ctx1 ctx2 = 0 && IntMap.equal (=) ctx1.var_bix ctx2.var_bix &&
  option_equal (BixMap.equal hty_eq) ctx1.forced_hterms_hty ctx2.forced_hterms_hty

(** Empty context. *)
let empty_ctx : ctx = mk_ctx IntMap.empty BixMap.empty None None

let string_of_ctx (ctx : ctx) : string =
  let bix_vars : IntSet.t BixMap.t =
    IntMap.fold (fun v (bix, ix) acc ->
        match BixMap.find_opt bix acc with
        | Some vars ->
          BixMap.add bix (IntSet.add v vars) acc
        | None ->
          BixMap.add bix (IntSet.singleton v) acc
      ) ctx.var_bix BixMap.empty
  in
  let bix_htys_strs =
    BixMap.fold (fun bix htys acc ->
        let vars =
          concat_map ", " string_of_int @@ IntSet.elements @@ BixMap.find bix bix_vars
        in
        let htys =
          concat_map " \\/ " string_of_hty @@ HtySet.elements htys
        in
        ("(" ^ vars ^ " : " ^ htys ^ ")") :: acc
      ) ctx.bix_htys []
  in
  let bix_htys_str =
    match bix_htys_strs with
    | [] -> "()"
    | _ -> String.concat ", " bix_htys_strs
  in
  let forced_hterms_hty_str =
    match ctx.forced_hterms_hty with
    | Some fbix_htys ->
      let fbix_htys_str =
        BixMap.bindings fbix_htys |> concat_map ", " (fun (bix, hty) ->
            string_of_int bix ^ " : " ^ string_of_hty hty
          )
      in
      " FHTY (" ^ fbix_htys_str ^ ")"
    | None -> ""
  in
  let forced_nt_ty_str =
    match ctx.forced_nt_ty with
    | Some (flocs, ftys) ->
      " FNT (" ^ concat_map ", " string_of_int (HlocSet.elements flocs) ^ " : " ^
      (concat_map " \\/ " string_of_ty @@ TySet.elements ftys) ^ ")"
    | None -> ""
  in
  bix_htys_str ^ forced_hterms_hty_str ^ forced_nt_ty_str
