open Binding
open Context
open DuplicationFactorGraph
open Environment
open Grammar
open GrammarCommon
open HGrammar
open HtyStore
open Main
open OUnit2
open Proof
open TargetEnvs
open Type
open Typing
open TypingCommon
open Utilities

(* --- helper functions --- *)

let init_flags () =
  Flags.verbose_all := false;
  Flags.type_format := "short";
  Flags.force_unsafe := false;
  Flags.no_headvar_opt := false;
  Flags.no_force_nt_ty_opt := false;
  Flags.no_force_hterms_hty_opt := false;
  Flags.quiet := true;
  Flags.propagate_flags ()

let rec paths_equal path1 path2 =
  match path1, path2 with
  | (nt_ty1, true) :: path1', (nt_ty2, true) :: path2'
  | (nt_ty1, false) :: path1', (nt_ty2, false) :: path2' ->
    nt_ty_eq nt_ty1 nt_ty2 && paths_equal path1' path2'
  | [], [] -> true
  | _, _ -> false

let string_of_raw_path =
  string_of_list (fun (vertex, edge_pos) ->
      string_of_nt_ty vertex ^ " (" ^ string_of_int (int_of_bool edge_pos) ^ ")"
    )

let assert_equal_paths (expected : (dfg_vertex * bool) list) (cycle_proof : cycle_proof) =
  assert_equal ~printer:string_of_raw_path ~cmp:paths_equal
    expected
    (cycle_proof#to_raw_edges)

let assert_equal_ctxs ctx1 ctx2 =
  assert_equal ~printer:string_of_ctx ~cmp:ctx_equal ctx1 ctx2

(** Asserts that two TEs are equal. Note that it uses default comparison, so it does not take
    into consideration that there are 3+ of a nonterminal or what terminals are used. *)
let assert_equal_tes te1 te2 =
  assert_equal ~printer:TargetEnvs.to_string ~cmp:TargetEnvs.equal
    (TargetEnvs.with_empty_temp_flags_and_locs te1)
    (TargetEnvs.with_empty_temp_flags_and_locs te2)

let mk_grammar rules =
  let nt_names = Array.mapi (fun i _ -> "N" ^ string_of_int i) rules in
  let g = new grammar nt_names [||] rules in
  print_verbose (not !Flags.quiet) @@ lazy (
    "Creating grammar:\n" ^ g#grammar_info ^ "\n"
  );
  EtaExpansion.eta_expand g;
  g

let mk_hgrammar g =
  new HGrammar.hgrammar g

let mk_cfa hg =
  let cfa = new Cfa.cfa hg in
  cfa#expand;
  cfa#compute_dependencies;
  cfa

let mk_typing g =
  let hg = mk_hgrammar g in
  (hg, new Typing.typing hg)

let mk_examples_typing filename =
  let g = Conversion.prerules2gram @@ Main.parse_file filename in
  EtaExpansion.eta_expand g;
  mk_typing g

let type_check_nt (typing : typing) (hg : hgrammar) (nt : nt_id) (target: ty) =
  typing#type_check (hg#nt_body nt) (Some target)

let type_check_nt_wo_ctx (typing : typing) (hg : hgrammar) (nt : nt_id) (target : ty) =
  type_check_nt typing hg nt target empty_ctx

let type_check_nt_wo_ctx_wo_target (typing : typing) (hg : hgrammar) (nt : nt_id) =
  typing#type_check (hg#nt_body nt) None empty_ctx

let senv positive v ity_str =
  (* nt in var is unused *)
  singleton_env empty_used_nts empty_loc_types positive (-1, v) @@ ity_of_string ity_str

let sctx typing ity_strs =
  let tys_list = List.map TySet.of_string ity_strs in
  let hty = Array.of_list @@ tys_list in
  let var_bix =
    IntMap.of_list @@ List.map (fun (ix, _) -> (ix, (0, ix))) @@ index_list tys_list
  in
  let bix_htys = IntMap.singleton 0 [hty] in
  mk_ctx var_bix (IntMap.map HtySet.of_list bix_htys) None None

let lctx var_bix (bix_htys : (int * ity list list) list) forced_hterms_hty forced_nt_ty : ctx =
  mk_ctx (IntMap.of_list var_bix) (IntMap.map (fun itys ->
      HtySet.of_list @@ List.map (fun itys ->
          Array.of_list @@
          List.map (fun ity -> TySet.of_ity ity) itys
        ) itys
    ) @@ IntMap.of_list bix_htys)
    (option_map BixMap.of_list forced_hterms_hty) forced_nt_ty

let list_sort_eq (l1 : 'a list list) (l2 : 'a list list) : bool =
  (List.sort (compare_lists compare) l1) =
  (List.sort (compare_lists compare) l2)

let string_of_ll = string_of_list (string_of_list string_of_int)

(** Fake hterm location. *)
(*let l : int = 0*)

let assert_regexp_count (expected_count : int) (regexp : Str.regexp) (str : string) : unit =
  let rec count_aux i count =
    if i > String.length str then
      count
    else
      try
        let pos = Str.search_forward regexp str i in
        count_aux (pos + 1) (count + 1)
      with
      | Not_found -> count
  in
  assert_equal ~printer:string_of_int expected_count @@ count_aux 0 0

let mk_proof nt ty used_nts positive =
  { derived = (nt, ty);
    used_nts = used_nts;
    loc_types = empty_loc_types;
    positive = positive;
    initial = false
  }

(* --- tests --- *)

let utilities_test () : test =
  "utilities" >::: [
    "range-0" >:: (fun _ ->
        assert_equal
          [0; 1; 2] @@
        range 0 3
      );

    "range-1" >:: (fun _ ->
        assert_equal
          [] @@
        range 1 1
      );
    
    "product-0" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [] @@
        product []
      );
    
    "product-1" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [[1]] @@
        product [[1]]
      );
    
    "product-2" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [[1; 2]] @@
        product [[1]; [2]]
      );
    
    "product-3" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [
            [1; 2; 3];
            [1; 2; 33];
            [1; 2; 333];
            [11; 2; 3];
            [11; 2; 33];
            [11; 2; 333]
          ] @@
        product [[1; 11]; [2]; [3; 33; 333]]
      );

    "product-4" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [
            [1; 2];
            [1; 22]
          ] @@
        product [[1]; [2; 22]]
      );

    "product-5" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [[1]; [2]] @@
        product [[1; 2]]
      );

    "flat_product-1" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq
          [] @@
        flat_product []
      );

    "flat_product-2" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq
          [] @@
        flat_product [[]]
      );

    "flat_product-3" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq
          [] @@
        flat_product [[]; []]
      );

    "flat_product-4" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq
          [
            [1; 2; 5];
            [1; 2; 6];
            [3; 4; 5];
            [3; 4; 6]
          ] @@
        flat_product [[[1; 2]; [3; 4]]; [[5]; [6]]]
      );
    
    "product_with_one_fixed-0" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [] @@
        product_with_one_fixed [] []
      );
    
    "product_with_one_fixed-1" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [[0]] @@
        product_with_one_fixed [[1; 2; 3]] [0]
      );
    
    "product_with_one_fixed-2" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [
            [0; 0];
            [0; 2];
            [0; 22];
            [1; 0];
            [11; 0]
          ] @@
        product_with_one_fixed [[1; 11]; [2; 22]] [0; 0]
      );
    
    "product_with_one_fixed-3" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [
            [0; 0; 0];
            [1; 0; 0];
            [0; 2; 0];
            [0; 0; 3];
            [0; 22; 0];
            [0; 222; 0];
            [1; 2; 0];
            [1; 0; 3];
            [1; 22; 0];
            [1; 222; 0];
            [0; 2; 3];
            [0; 22; 3];
            [0; 222; 3]
          ] @@
        product_with_one_fixed [[1]; [2; 22; 222]; [3]] [0; 0; 0]
      );
    
    "product_with_one_fixed-4" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq ~printer:string_of_ll
          [
            [0; 0; 0; 0];
            [1; 0; 0; 0];
            [0; 2; 0; 0];
            [0; 0; 3; 0];
            [0; 0; 0; 4];
            [1; 2; 0; 0];
            [1; 0; 3; 0];
            [1; 0; 0; 4];
            [0; 2; 3; 0];
            [0; 2; 0; 4];
            [0; 0; 3; 4];
            [0; 2; 3; 4];
            [1; 0; 3; 4];
            [1; 2; 0; 4];
            [1; 2; 3; 0]
          ] @@
        product_with_one_fixed [[1]; [2]; [3]; [4]] [0; 0; 0; 0]
      );
  ]



let ctx_test () : test =
  "context" >::: [
    "req-sat-0" >:: (fun _ ->
        let bix_htys = [(0, [[ity_top]]); (1, [[ity_top]])] in
        let ctx = lctx [] bix_htys None None in
        assert_equal true @@ ctx_requirements_satisfied ctx
      );

    (* some herms can have empty types as long as they are unused *)
    "req-sat-1" >:: (fun _ ->
        let bix_htys = [(0, []); (1, [[ity_top]])] in
        let ctx = lctx [] bix_htys None None in
        assert_equal true @@ ctx_requirements_satisfied ctx
      );

    (* nt requirement not satisfied and impossible to satisfy *)
    "req-sat-2" >:: (fun _ ->
        let bix_htys = [(0, [[ity_top]]); (1, [[ity_top]])] in
        let ctx = lctx [] bix_htys None (Some ([], TySet.singleton ty_pr)) in
        assert_equal false @@ ctx_requirements_satisfied ctx
      );

    (* nt requirement not satisfied *)
    "req-sat-3" >:: (fun _ ->
        let bix_htys = [(0, [[ity_top]]); (1, [[ity_top]])] in
        let ctx = lctx [] bix_htys None (Some ([1], TySet.singleton ty_pr)) in
        assert_equal false @@ ctx_requirements_satisfied ctx
      );

    (* hterms requirement not satisfied *)
    "req-sat-4" >:: (fun _ ->
        let bix_htys = [(0, [[ity_top]]); (1, [[ity_top]])] in
        let ctx = lctx [] bix_htys (Some [(0, [|tys_top|]); (1, [|tys_top|])]) None in
        assert_equal false @@ ctx_requirements_satisfied ctx
      );

    "combinations-0" >:: (fun _ ->
        let bix_htys = [
            (0, [[ity_top]; [ity_of_string "pr"]; [ity_of_string "np"]]);
            (1, [[ity_of_string "pr"]; [ity_of_string "np"]]);
            (2, [[ity_top]; [ity_of_string "pr"]; [ity_of_string "np"]])
          ] in
        let ctx = lctx [] bix_htys None None in
        assert_equal ~printer:string_of_int 18 @@ ctx_var_combinations ctx
      );

    "combinations-1" >:: (fun _ ->
        let bix_htys = [
            (0, [[ity_top]; [ity_of_string "pr"]; [ity_of_string "np"]]);
            (1, [[ity_of_string "pr"]; [ity_of_string "np"]]);
            (2, [[ity_top]; [ity_of_string "pr"]; [ity_of_string "np"]])
          ] in
        let ctx = lctx [] bix_htys (Some [(0, [|tys_top|])]) None in
        assert_equal ~printer:string_of_int 6 @@ ctx_var_combinations ctx
      );

    "combinations-2" >:: (fun _ ->
        let bix_htys = [
            (0, [[ity_top]; [ity_of_string "pr"]; [ity_of_string "np"]]);
            (1, [[ity_of_string "pr"]; [ity_of_string "np"]]);
            (2, [[ity_top]; [ity_of_string "pr"]; [ity_of_string "np"]])
          ] in
        let ctx = lctx [] bix_htys (Some [(0, [|tys_top|]); (2, [|tys_top|])]) None in
        assert_equal ~printer:string_of_int 10 @@ ctx_var_combinations ctx
      );

    "combinations-3" >:: (fun _ ->
        let bix_htys = [
            (0, [[ity_top]; [ity_of_string "pr"]; [ity_of_string "np"]]);
            (1, [[ity_of_string "pr"]; [ity_of_string "np"]]);
            (2, [[ity_top]; [ity_of_string "pr"]; [ity_of_string "np"]])
          ] in
        let ctx = lctx [] bix_htys (Some []) None in
        assert_equal ~printer:string_of_int 0 @@ ctx_var_combinations ctx
      );

    "combinations-4" >:: (fun _ ->
        let bix_htys = [
            (0, [[ity_top]; [ity_of_string "pr"]; [ity_of_string "np"]]);
            (1, [[ity_of_string "pr"]; [ity_of_string "np"]]);
            (2, [])
          ] in
        let ctx = lctx [] bix_htys None None in
        assert_equal ~printer:string_of_int 0 @@ ctx_var_combinations ctx
      );

    "combinations-5" >:: (fun _ ->
        let bix_htys = [
            (0, [[ity_top]; [ity_of_string "pr"]; [ity_of_string "np"]]);
            (1, [[ity_of_string "pr"]; [ity_of_string "np"]]);
            (2, [[ity_top]; [ity_of_string "pr"]; [ity_of_string "np"]])
          ] in
        let tys_pr = [|TySet.of_string "pr"|] in
        let ctx = lctx [] bix_htys
            (Some [
                (0, tys_pr);
                (1, tys_pr);
                (2, tys_pr)
              ]) None in
        assert_equal ~printer:string_of_int 14 @@ ctx_var_combinations ctx
      );

    "combinations-6" >:: (fun _ ->
        let bix_htys = [
            (0, [[ity_top]; [ity_of_string "pr"]; [ity_of_string "np"]]);
            (1, [[ity_top]; [ity_of_string "pr"]; [ity_of_string "np"]])
          ] in
        let ctx = lctx [] bix_htys (Some [(0, [|tys_top|]); (1, [|tys_top|])]) None in
        assert_equal ~printer:string_of_int 5 @@ ctx_var_combinations ctx
      );

    "split-var-0" >:: (fun _ ->
        let var_bix = [(0, (0, 0))] in
        let bix_htys = [
            (0, [[ity_of_string "pr"]; [ity_of_string "np"]])
          ] in
        let ctx = lctx var_bix bix_htys None None in
        assert_equal ~printer:(string_of_list string_of_int) [1; 1] @@
        List.sort compare @@
        List.map (fun (ty, ctx) -> ctx_var_combinations ctx) @@
        ctx_split_var ctx (0, 0)
      );

    "split-var-1" >:: (fun _ ->
        let var_bix = [(0, (0, 0)); (1, (1, 0))] in
        let bix_htys = [
            (0, [[ity_of_string "pr"]; [ity_of_string "np"]]);
            (1, [[ity_of_string "pr"]; [ity_of_string "np"]])
          ] in
        let tys_pr = [|TySet.of_string "pr"|] in
        let ctx = lctx var_bix bix_htys (Some [
            (0, tys_pr);
            (1, tys_pr)
          ]) None in
        assert_equal ~printer:(string_of_list string_of_int) [1; 2] @@
        List.sort compare @@
        List.map (fun (ty, ctx) -> ctx_var_combinations ctx) @@
        ctx_split_var ctx (0, 0)
      );
    
    "split-var-2" >:: (fun _ ->
        let var_bix = [(0, (0, 0)); (1, (0, 1))] in
        let bix_htys = [
          (0, [[ity_of_string "pr"; ity_of_string "pr"];
               [ity_of_string "pr"; ity_of_string "np"]])
        ] in
        let ctx = lctx var_bix bix_htys None None in
        match ctx_split_var ctx (0, 0) with
        | [(ty, c)] ->
          assert_equal ~cmp:Ty.equal ty ty_pr;
          assert_equal ~cmp:ctx_equal
            (lctx var_bix bix_htys None None)
            c
        | _ -> assert_failure "expected singleton"
      );

    "enforce-var-0" >:: (fun _ ->
        let var_bix = [(0, (0, 0))] in
        let bix_htys = [
            (0, [[ity_of_string "pr"]; [ity_of_string "np"]])
          ] in
        let ctx = lctx var_bix bix_htys None None in
        assert_equal ~printer:string_of_int 1 @@
        ctx_var_combinations @@ snd @@ option_get @@
        ctx_enforce_var ctx (0, 0) ty_pr
      );

    "enforce-var-1" >:: (fun _ ->
        let var_bix = [(0, (0, 0)); (1, (1, 0))] in
        let bix_htys = [
            (0, [[ity_of_string "pr"]; [ity_of_string "np"]]);
            (1, [[ity_of_string "pr"]; [ity_of_string "np"]])
          ] in
        let tys_pr = [|TySet.of_string "pr"|] in
        let ctx = lctx var_bix bix_htys (Some [
            (0, tys_pr);
            (1, tys_pr)
          ]) None in
        assert_equal ~printer:string_of_int 1 @@
        ctx_var_combinations @@ snd @@ option_get @@
        ctx_enforce_var ctx (0, 0) ty_np
      );

    "enforce-var-2" >:: (fun _ ->
        let var_bix = [(0, (0, 0)); (1, (1, 0))] in
        let bix_htys = [
            (0, [[ity_of_string "pr"]; [ity_of_string "np"]]);
            (1, [[ity_of_string "pr"]; [ity_of_string "np"]])
          ] in
        let tys_np = [|TySet.of_string "np"|] in
        let ctx = lctx var_bix bix_htys (Some [(0, tys_np)]) None in
        assert_equal ~printer:string_of_int 2 @@
        ctx_var_combinations @@ snd @@ option_get @@
        ctx_enforce_var ctx (0, 0) ty_np
      );

    "enforce-var-3" >:: (fun _ ->
        let var_bix = [(0, (0, 0)); (1, (1, 0))] in
        let bix_htys = [
            (0, [[ity_of_string "T -> pr"]; [ity_of_string "T -> np"]]);
            (1, [[ity_of_string "T -> pr"]; [ity_of_string "T -> np"]])
          ] in
        let ctx = lctx var_bix bix_htys (Some [
            (0, [|TySet.of_string "T -> pr"|]);
            (1, [|TySet.of_string "T -> pr"|])
          ]) None in
        assert_equal None @@
        ctx_enforce_var ctx (0, 0) @@ ty_of_string "pr -> pr"
      );
    
    "enforce-var-4" >:: (fun _ ->
        let var_bix = [(0, (0, 0)); (1, (1, 0))] in
        let bix_htys = [
          (0, [[ity_of_string "pr"]; [ity_of_string "np"]]);
          (1, [[ity_of_string "pr"]; [ity_of_string "np"]])
        ] in
        let bix_htys2 = [
          (0, [[ity_of_string "pr"]]);
          (1, [[ity_of_string "pr"]; [ity_of_string "np"]])
        ] in
        let tys_pr = [|TySet.of_string "pr"|] in
        let ctx = lctx var_bix bix_htys (Some [
            (0, tys_pr);
            (1, tys_pr)
          ]) None in
        assert_equal ~cmp:ctx_equal
          (lctx var_bix bix_htys2 None None) @@
        snd @@ option_get @@
        ctx_enforce_var ctx (0, 0) ty_pr
      );

    "enforce-var-5" >:: (fun _ ->
        let var_bix = [(0, (0, 0)); (1, (1, 0)); (2, (2, 0))] in
        let bix_htys = [
          (0, [[ity_of_string "pr"]; [ity_of_string "np"]]);
          (1, [[ity_of_string "pr"]; [ity_of_string "np"]]);
          (2, [[ity_of_string "pr"]; [ity_of_string "np"]])
        ] in
        let bix_htys2 = [
          (0, [[ity_of_string "np"]]);
          (1, [[ity_of_string "pr"]; [ity_of_string "np"]]);
          (2, [[ity_of_string "pr"]; [ity_of_string "np"]])
        ] in
        let tys_pr = [|TySet.of_string "pr"|] in
        let ctx = lctx var_bix bix_htys (Some [
            (0, tys_pr);
            (1, tys_pr);
            (2, tys_pr)
          ]) None in
        assert_equal ~printer:string_of_ctx ~cmp:ctx_equal
          (lctx var_bix bix_htys2 (Some [
               (1, tys_pr);
               (2, tys_pr)
             ]) None) @@
        snd @@ option_get @@
        ctx_enforce_var ctx (0, 0) ty_np
      );

    "split-nt-0" >:: (fun _ ->
        let nt_ity = [|TySet.of_string "np /\\ pr"|] in
        let ctx = lctx [] [] None None in
        let res = ctx_split_nt ctx nt_ity 0 0 in
        assert_equal ~printer:string_of_ity (ity_of_string "np /\\ pr") @@
        TyList.of_list @@ List.map fst res;
        assert_equal 0 @@ ctx_compare (snd @@ List.nth res 0) (snd @@ List.nth res 0)
      );

    "split-nt-1" >:: (fun _ ->
        let nt_ity = [|TySet.of_string "np /\\ pr"|] in
        let ctx = lctx [] [] None @@ Some ([0; 1; 2], TySet.singleton ty_np) in
        let res = ctx_split_nt ctx nt_ity 0 0 in
        assert_equal ~printer:string_of_ity (ity_of_string "np /\\ pr") @@
        TyList.of_list @@ List.map fst res;
        let forced_locs = List.map (fun (_, ctx) -> option_map fst ctx.forced_nt_ty) res in
        assert_equal ~printer:(string_of_list @@ string_of_list string_of_int)
          [[1; 2]; [42]] @@
        List.sort compare @@
        List.map (option_map_or_default [42] HlocSet.elements) forced_locs
      );

    "split-nt-2" >:: (fun _ ->
        let nt_ity = [|TySet.of_string "np /\\ pr"|] in
        let ctx = lctx [] [] None @@ Some ([0], TySet.singleton ty_np) in
        let res = ctx_split_nt ctx nt_ity 0 0 in
        assert_equal ~printer:string_of_ity (ity_of_string "np") @@
        TyList.of_list @@ List.map fst res;
        let forced_locs = List.map (fun (_, ctx) -> option_map fst ctx.forced_nt_ty) res in
        assert_equal [None] forced_locs
      );

    "enforce-nt-0" >:: (fun _ ->
        let nt_ity = [|TySet.of_string "np /\\ pr"|] in
        let ctx = lctx [] [] None None in
        assert_equal ~printer:string_of_bool true @@
        is_some @@ ctx_enforce_nt ctx nt_ity 0 0 ty_pr
      );

    (* enforcing nt when there are no nt restrictions does not change anything *)
    "enforce-nt-1" >:: (fun _ ->
        let nt_ity = [|TySet.of_string "np -> np /\\ pr -> pr"|] in
        let ctx = lctx [] [] None None in
        assert_equal ~printer:string_of_bool true @@
        is_some @@ ctx_enforce_nt ctx nt_ity 0 0 @@ ty_of_string "np -> np"
      );
    
    "enforce-nt-2" >:: (fun _ ->
        let nt_ity = [|TySet.of_string "np /\\ pr"|] in
        let ctx = lctx [] [] None @@ Some ([0], TySet.singleton ty_np) in
        assert_equal ~printer:string_of_bool true @@
        is_some @@ ctx_enforce_nt ctx nt_ity 0 0 ty_np
      );

    "enforce-nt-3" >:: (fun _ ->
        let nt_ity = [|TySet.of_string "np /\\ pr"|] in
        let ctx = lctx [] [] None @@ Some ([0], TySet.singleton ty_np) in
        assert_equal ~printer:string_of_bool false @@
        is_some @@ ctx_enforce_nt ctx nt_ity 0 0 ty_pr
      );

    (* enforcing nt when nt can't have that type *)
    "enforce-nt-4" >:: (fun _ ->
        let nt_ity = [|TySet.of_string "np -> np /\\ pr -> pr"|] in
        let ctx = lctx [] [] None None in
        assert_equal ~printer:string_of_bool false @@
        is_some @@ ctx_enforce_nt ctx nt_ity 0 0 @@ ty_of_string "np -> pr"
      );

    "enforce-nt-5" >:: (fun _ ->
        let nt_ity = [|TySet.of_string "np /\\ pr"|] in
        let ctx = lctx [] [] None @@ Some ([0], TySet.of_string "np /\\ pr") in
        assert_equal ~printer:string_of_bool true @@
        is_some @@ ctx_enforce_nt ctx nt_ity 0 0 ty_np
      );

    "enforce-nt-6" >:: (fun _ ->
        let nt_ity = [|TySet.of_string "np /\\ pr"|] in
        let ctx = lctx [] [] None @@ Some ([0; 1; 2], TySet.of_string "pr") in
        let ctx2 = lctx [] [] None @@ Some ([1; 2], TySet.of_string "pr") in
        assert_equal ~printer:string_of_ctx ~cmp:ctx_equal ctx2 @@
        snd @@ option_get @@ ctx_enforce_nt ctx nt_ity 0 0 ty_np
      );

    "intersect-0" >:: (fun _ ->
        let ctx1 = lctx [] [] None @@ Some ([0; 1], TySet.singleton ty_np) in
        let ctx2 = lctx [] [] None @@ Some ([1; 2], TySet.singleton ty_np) in
        let ctx = intersect_ctxs ctx1 ctx2 in
        let expected = lctx [] [] None @@ Some ([1], TySet.singleton ty_np) in
        assert_equal ~cmp:ctx_equal expected @@ option_get ctx
      );

    "intersect-1" >:: (fun _ ->
        let ctx1 = lctx [] [] None @@ Some ([0], TySet.singleton ty_np) in
        let ctx2 = lctx [] [] None @@ Some ([2], TySet.singleton ty_np) in
        let ctx = intersect_ctxs ctx1 ctx2 in
        assert_equal None ctx
      );

    "intersect-2" >:: (fun _ ->
        let ctx1 = lctx [] [] None None in
        let ctx2 = lctx [] [] None None in
        let ctx = intersect_ctxs ctx1 ctx2 in
        assert_equal ~cmp:ctx_equal ctx1 @@ option_get ctx
      );

    "intersect-3" >:: (fun _ ->
        let var_bix = [(0, (0, 0)); (1, (1, 0))] in
        let bix_htys1 = [
            (0, [[ity_top]; [ity_of_string "T -> pr"]]);
            (1, [[ity_of_string "T -> pr"]; [ity_of_string "T -> np"]])
          ] in
        let bix_htys2 = [
            (0, [[ity_of_string "T -> pr"]; [ity_of_string "T -> np"]]);
            (1, [[ity_of_string "T -> pr"]; [ity_of_string "T -> np"]])
          ] in
        let expected_bix_htys = [
            (0, [[ity_of_string "T -> pr"]]);
            (1, [[ity_of_string "T -> pr"]; [ity_of_string "T -> np"]])
          ] in
        let ctx1 = lctx var_bix bix_htys1 None None in
        let ctx2 = lctx var_bix bix_htys2 None None in
        let ctx = intersect_ctxs ctx1 ctx2 in
        let expected = lctx var_bix expected_bix_htys None None in
        assert_equal ~cmp:ctx_equal expected @@ option_get ctx
      );

    (* When one of hterms' types product elements intersection is empty, but one of intersected
       ones is not empty, there were conflicting assumptions. *)
    "intersect-4" >:: (fun _ ->
        let var_bix = [(0, (0, 0)); (1, (1, 0))] in
        let bix_htys1 = [
            (0, [[ity_top]; [ity_of_string "T -> np"]]);
            (1, [[ity_of_string "T -> pr"]; [ity_of_string "T -> np"]])
          ] in
        let bix_htys2 = [
            (0, [[ity_of_string "pr -> pr"]; [ity_of_string "T -> pr"]]);
            (1, [[ity_of_string "T -> pr"]; [ity_of_string "T -> np"]])
          ] in
        let ctx1 = lctx var_bix bix_htys1 None None in
        let ctx2 = lctx var_bix bix_htys2 None None in
        let ctx = intersect_ctxs ctx1 ctx2 in
        assert_equal None ctx
      );

    (* When due to intersection a single element remains and it is forced, the condition
       is satisfied. *)
    "intersect-5" >:: (fun _ ->
        let var_bix = [(0, (0, 0)); (1, (1, 0))] in
        let bix_htys1 = [
            (0, [[ity_top]; [ity_of_string "T -> np"]]);
            (1, [[ity_of_string "T -> pr"]; [ity_of_string "T -> np"]])
          ] in
        let bix_htys2 = [
            (0, [[ity_of_string "T -> np"]; [ity_of_string "T -> pr"]]);
            (1, [[ity_of_string "T -> pr"]; [ity_of_string "T -> np"]])
          ] in
        let expected_bix_htys = [
            (0, [[ity_of_string "T -> np"]]);
            (1, [[ity_of_string "T -> pr"]; [ity_of_string "T -> np"]])
          ] in
        let forced_hterms_hty = Some [
            (0, [|TySet.of_string "T -> np"|]);
            (1, [|TySet.of_string "T -> np"|])
          ] in
        let ctx1 = lctx var_bix bix_htys1 forced_hterms_hty None in
        let ctx2 = lctx var_bix bix_htys2 forced_hterms_hty None in
        let ctx = intersect_ctxs ctx1 ctx2 in
        let expected = lctx var_bix expected_bix_htys None None in
        assert_equal ~cmp:ctx_equal expected @@ option_get ctx;
        assert_equal None (option_get ctx).forced_hterms_hty
      );

    "intersect-6" >:: (fun _ ->
        let var_bix = [(0, (0, 0)); (1, (1, 0))] in
        let bix_htys1 = [
            (0, [[ity_top]; [ity_of_string "T -> np"]]);
            (1, [[ity_of_string "T -> pr"]])
          ] in
        let bix_htys2 = [
            (0, [[ity_of_string "T -> pr"]]);
            (1, [[ity_of_string "T -> pr"]; [ity_of_string "T -> np"]])
          ] in
        let forced_hterms_hty = Some [
            (0, [|TySet.of_string "T -> np"|]);
            (1, [|TySet.of_string "T -> np"|])
          ] in
        let ctx1 = lctx var_bix bix_htys1 forced_hterms_hty None in
        let ctx2 = lctx var_bix bix_htys2 forced_hterms_hty None in
        let ctx = intersect_ctxs ctx1 ctx2 in
        assert_equal None ctx
      );

    "intersect-7" >:: (fun _ ->
        let ctx1 =
          lctx [(0, (0, 0)); (1, (1, 0))]
            ([(0, [[sty ty_pr]]); (1, [[sty ty_np]; [sty ty_pr]])])
            None None
        in
        let ctx2 =
          lctx [(0, (0, 0)); (1, (1, 0))]
            [(0, [[sty ty_np]; [sty ty_pr]]); (1, [[sty ty_np]])]
            None None
        in
        let ctx12 =
          lctx [(0, (0, 0)); (1, (1, 0))]
            [(0, [[sty ty_pr]]); (1, [[sty ty_np]])]
            None None
        in
        assert_equal ~cmp:(option_equal ctx_equal) (Some ctx12) @@ intersect_ctxs ctx1 ctx2;
        assert_equal ~cmp:(option_equal ctx_equal) (Some ctx2) @@ intersect_ctxs ctx2 ctx2;
        assert_equal ~cmp:(option_equal ctx_equal) (Some ctx1) @@ intersect_ctxs ctx1 ctx1
      );

    "intersect-8" >:: (fun _ ->
        let var_bix = [(0, (0, 0)); (1, (1, 0)); (2, (2, 0)); (3, (3, 0))] in
        let bix_htys1 = [
          (0, [[ity_of_string "T -> pr"]; [ity_of_string "T -> np"]]);
          (1, [[ity_of_string "T -> pr"]; [ity_of_string "T -> np"]]);
          (2, [[ity_of_string "T -> pr"]]);
          (3, [[ity_of_string "T -> pr"]])
        ] in
        let bix_htys2 = [
          (0, [[ity_of_string "T -> pr"]]);
          (1, [[ity_of_string "T -> pr"]]);
          (2, [[ity_of_string "T -> pr"]; [ity_of_string "T -> np"]]);
          (3, [[ity_of_string "T -> pr"]; [ity_of_string "T -> np"]])
        ] in
        let forced_hterms_hty1 = Some [
            (0, [|TySet.of_string "T -> np"|]);
            (1, [|TySet.of_string "T -> np"|])
          ] in
        let forced_hterms_hty2 = Some [
            (2, [|TySet.of_string "T -> np"|]);
            (3, [|TySet.of_string "T -> np"|])
          ] in
        let ctx1 = lctx var_bix bix_htys1 forced_hterms_hty1 None in
        let ctx2 = lctx var_bix bix_htys2 forced_hterms_hty2 None in
        assert_equal None @@ intersect_ctxs ctx1 ctx2
      );
  ]



let dfg_test () : test =
  "dfg" >::: [
    (* one node, no edges *)
    "dfg-0" >:: (fun _ ->
        assert_equal None @@
        (
          let dfg = new dfg in
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_np empty_used_nts false;
          dfg
        )#find_positive_cycle 0 ty_np
      );

    (* unreachable loop *)
    "dfg-1" >:: (fun _ ->
        assert_equal None @@
        (
          let dfg = new dfg in
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_np empty_used_nts false;
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_pr empty_used_nts true;
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_pr (nt_ty_used_once 0 ty_pr) true;
          dfg
        )#find_positive_cycle 0 ty_np
      );

    (* positive loop at start *)
    "dfg-2" >:: (fun _ ->
        assert_equal_paths
          [((0, ty_pr), true); ((0, ty_pr), false)] @@
        option_get @@ (
          let dfg = new dfg in
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_pr empty_used_nts true;
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_pr (nt_ty_used_once 0 ty_pr) true;
          dfg
        )#find_positive_cycle 0 ty_pr
      );

    (* non-positive loop at start *)
    "dfg-3" >:: (fun _ ->
        assert_equal None @@
        (
          let dfg = new dfg in
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_np empty_used_nts false;
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_np (nt_ty_used_once 0 ty_np) false;
          dfg
        )#find_positive_cycle 0 ty_np
      );

    (* non-positive and positive interconnected loops *)
    "dfg-4" >:: (fun _ ->
        assert_equal_paths
          [((0, ty_np), false); ((1, ty_np), true); ((2, ty_pr), false);
           ((3, ty_np), false); ((1, ty_np), false)] @@
        option_get @@ (
          let dfg = new dfg in
          ignore @@ dfg#add_vertex @@ mk_proof 3 ty_np empty_used_nts false;
          ignore @@ dfg#add_vertex @@ mk_proof 2 ty_pr (nt_ty_used_once 3 ty_np) false;
          ignore @@ dfg#add_vertex @@ mk_proof 1 ty_np (nt_ty_used_once 2 ty_pr) true;
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_np (nt_ty_used_once 1 ty_np) false;
          ignore @@ dfg#add_vertex @@ mk_proof 4 ty_np (nt_ty_used_once 3 ty_np) false;
          ignore @@ dfg#add_vertex @@ mk_proof 1 ty_np (nt_ty_used_once 4 ty_np) false;
          ignore @@ dfg#add_vertex @@ mk_proof 3 ty_np (nt_ty_used_once 1 ty_np) false;
          dfg
        )#find_positive_cycle 0 ty_np
      );

    (* non-positive and positive interconnected loops - another order *)
    "dfg-5" >:: (fun _ ->
        assert_equal_paths
          [((0, ty_np), false); ((1, ty_np), true); ((4, ty_np), false);
           ((3, ty_np), false); ((1, ty_np), false)] @@
        option_get @@ (
          let dfg = new dfg in
          ignore @@ dfg#add_vertex @@ mk_proof 3 ty_np empty_used_nts false;
          ignore @@ dfg#add_vertex @@ mk_proof 2 ty_pr (nt_ty_used_once 3 ty_np) false;
          ignore @@ dfg#add_vertex @@ mk_proof 1 ty_np (nt_ty_used_once 2 ty_pr) false;
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_np (nt_ty_used_once 1 ty_np) false;
          ignore @@ dfg#add_vertex @@ mk_proof 4 ty_np (nt_ty_used_once 3 ty_np) false;
          ignore @@ dfg#add_vertex @@ mk_proof 1 ty_np (nt_ty_used_once 4 ty_np) true;
          ignore @@ dfg#add_vertex @@ mk_proof 3 ty_np (nt_ty_used_once 1 ty_np) false;
          dfg
        )#find_positive_cycle 0 ty_np
      );

    (* non-positive loop and positive path *)
    "dfg-6" >:: (fun _ ->
        assert_equal None @@
        (
          let dfg = new dfg in
          ignore @@ dfg#add_vertex @@ mk_proof 1 ty_np empty_used_nts false;
          ignore @@ dfg#add_vertex @@ mk_proof 5 ty_np (nt_ty_used_once 1 ty_np) false;
          ignore @@ dfg#add_vertex @@ mk_proof 4 ty_np (nt_ty_used_once 5 ty_np) false;
          ignore @@ dfg#add_vertex @@ mk_proof 1 ty_np (nt_ty_used_once 4 ty_np) false;
          ignore @@ dfg#add_vertex @@ mk_proof 3 ty_np empty_used_nts false;
          ignore @@ dfg#add_vertex @@ mk_proof 2 ty_pr (nt_ty_used_once 3 ty_np) false;
          ignore @@ dfg#add_vertex @@ mk_proof 1 ty_np (nt_ty_used_once 2 ty_pr) true;
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_np (nt_ty_used_once 1 ty_np) false;
          dfg
        )#find_positive_cycle 0 ty_np
      );

    (* registering twice the same vertex *)
    "dfg-7" >:: (fun _ ->
        assert_equal_paths
          [((0, ty_pr), true); ((0, ty_pr), false)] @@
        option_get @@ (
          let dfg = new dfg in
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_pr empty_used_nts true;
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_pr (nt_ty_used_once 0 ty_pr) true;
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_pr (nt_ty_used_once 0 ty_pr) false;
          dfg
        )#find_positive_cycle 0 ty_pr
      );

    (* checking for not registered vertex *)
    "dfg-8" >:: (fun _ ->
        assert_equal None @@
        (
          let dfg = new dfg in
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_pr empty_used_nts true;
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_pr (nt_ty_used_once 0 ty_pr) true;
          dfg
        )#find_positive_cycle 0 ty_np
      );

    (* cycle at start, but not on the same vertex *)
    "dfg-9" >:: (fun _ ->
        assert_equal_paths
          [((0, ty_pr), true); ((1, ty_pr), true); ((0, ty_pr), false)] @@
        option_get @@ (
          let dfg = new dfg in
          ignore @@ dfg#add_vertex @@ mk_proof 1 ty_pr empty_used_nts true;
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_pr (nt_ty_used_once 1 ty_pr) true;
          ignore @@ dfg#add_vertex @@ mk_proof 1 ty_pr (nt_ty_used_once 0 ty_pr) true;
          dfg
        )#find_positive_cycle 0 ty_pr
      );

    (* two cycles, one shorter, the shorter one should be selected *)
    "dfg-10" >:: (fun _ ->
        assert_equal_paths
          [((0, ty_pr), false); ((4, ty_pr), false); ((3, ty_pr), true); ((0, ty_pr), false)] @@
        option_get @@ (
          let dfg = new dfg in
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_pr empty_used_nts false;
          ignore @@ dfg#add_vertex @@ mk_proof 3 ty_pr (nt_ty_used_once 0 ty_pr) true;
          ignore @@ dfg#add_vertex @@ mk_proof 2 ty_pr (nt_ty_used_once 3 ty_pr) false;
          ignore @@ dfg#add_vertex @@ mk_proof 1 ty_pr (nt_ty_used_once 2 ty_pr) false;
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_pr (nt_ty_used_once 1 ty_pr) false;
          ignore @@ dfg#add_vertex @@ mk_proof 4 ty_pr (nt_ty_used_once 3 ty_pr) false;
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_pr (nt_ty_used_once 4 ty_pr) false;
          dfg
        )#find_positive_cycle 0 ty_pr
      );

    (* two cycles, one shorter - another order, the shorter one should be selected *)
    "dfg-11" >:: (fun _ ->
        assert_equal_paths
          [((0, ty_pr), false); ((1, ty_pr), false); ((2, ty_pr), true); ((0, ty_pr), false)] @@
        option_get @@ (
          let dfg = new dfg in
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_pr empty_used_nts false;
          ignore @@ dfg#add_vertex @@ mk_proof 2 ty_pr (nt_ty_used_once 0 ty_pr) true;
          ignore @@ dfg#add_vertex @@ mk_proof 1 ty_pr (nt_ty_used_once 2 ty_pr) false;
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_pr (nt_ty_used_once 1 ty_pr) false;
          ignore @@ dfg#add_vertex @@ mk_proof 4 ty_pr (nt_ty_used_once 2 ty_pr) false;
          ignore @@ dfg#add_vertex @@ mk_proof 3 ty_pr (nt_ty_used_once 4 ty_pr) false;
          ignore @@ dfg#add_vertex @@ mk_proof 0 ty_pr (nt_ty_used_once 3 ty_pr) false;
          dfg
        )#find_positive_cycle 0 ty_pr
      );

    (* add_vertex should return whether new edge was added, checking other data *)
    "dfg-12" >:: (fun _ ->
        let proof1 = mk_proof 0 ty_np empty_used_nts false in
        let proof2 = mk_proof 0 ty_pr (nt_ty_used_once 0 ty_np) true in
        let proof3 = mk_proof 0 ty_pr (nt_ty_used_once 0 ty_np) false in
        let proof4 = mk_proof 0 ty_pr (nt_ty_used_once 0 ty_pr) true in
        let dfg = new dfg in
        assert_equal None @@ dfg#find_positive_cycle 0 ty_pr;
        (* note that no edge is added, only vertex, so expecting false *)
        assert_equal false @@ dfg#add_vertex proof1;
        assert_equal None @@ dfg#find_positive_cycle 0 ty_pr;
        assert_equal true @@ dfg#add_vertex proof3;
        (* edge should be replaced with positive one *)
        assert_equal true @@ dfg#add_vertex proof2;
        assert_equal None @@ dfg#find_positive_cycle 0 ty_pr;
        (* these edges should be ignored as there is already a positive edge present there *)
        assert_equal false @@ dfg#add_vertex proof2;
        assert_equal false @@ dfg#add_vertex proof3;
        assert_equal None @@ dfg#find_positive_cycle 0 ty_pr;
        assert_equal true @@ dfg#add_vertex proof4;
        let cycle = option_get @@ dfg#find_positive_cycle 0 ty_pr in
        let path_to_cycle, cycle, escape, proofs = cycle#raw_data in
        assert_equal 0 @@ List.length path_to_cycle;
        assert_equal 1 @@ List.length cycle;
        assert_equal proof4 @@ fst @@ List.hd cycle;
        (* no need to define custom equality, since dfg modifies only initial flag *)
        assert_equal {proof3 with initial = true} escape;
        assert_equal 3 @@ List.length proofs
      );

    (* checking a border case where initial proof tree crosses path to cycle - this is another
       case aside from escape vertex where the same vertex can be included in list of proofs
       twice. *)
    "dfg-13" >:: (fun _ ->
        let dfg = new dfg in
        (* 10, 11 <- 9 <- 2 *)
        ignore @@ dfg#add_vertex @@ mk_proof 10 ty_np empty_used_nts false;
        ignore @@ dfg#add_vertex @@ mk_proof 11 ty_np empty_used_nts false;
        ignore @@ dfg#add_vertex @@ mk_proof 9 ty_pr
          (NTTyMap.of_list [((10, ty_np), false); ((11, ty_np), false)]) true;
        ignore @@ dfg#add_vertex @@ mk_proof 2 ty_pr
          (NTTyMap.of_list [((9, ty_pr), false)]) false;
        (* 8, 2 <- 5 *)
        ignore @@ dfg#add_vertex @@ mk_proof 8 ty_np empty_used_nts false;
        ignore @@ dfg#add_vertex @@ mk_proof 5 ty_pr
          (NTTyMap.of_list [((2, ty_pr), false); ((8, ty_np), false)]) false;
        (* 5 <- 7 *)
        ignore @@ dfg#add_vertex @@ mk_proof 7 ty_pr
          (NTTyMap.of_list [((5, ty_pr), false)]) false;
        (* 8 <- 6 *)
        ignore @@ dfg#add_vertex @@ mk_proof 6 ty_pr
          (NTTyMap.of_list [((8, ty_np), true)]) true;
        (* cycle: 5 : pr, 6 : pr <- 4 : pr; 4 : pr, 6 : pr <- 5 : pr *)
        ignore @@ dfg#add_vertex @@ mk_proof 4 ty_pr
          (NTTyMap.of_list [((5, ty_pr), false); ((6, ty_pr), false)]) false;
        ignore @@ dfg#add_vertex @@ mk_proof 5 ty_pr
          (NTTyMap.of_list [((4, ty_pr), false); ((6, ty_pr), false)]) false;
        (* 7 <- 4 - this should be ignored *)
        ignore @@ dfg#add_vertex @@ mk_proof 4 ty_pr
          (NTTyMap.of_list [((7, ty_pr), false)]) false;
        (* 4 <- 3 <- 2 <- 1 <- 0 *)
        ignore @@ dfg#add_vertex @@ mk_proof 3 ty_pr
          (NTTyMap.of_list [((4, ty_pr), false)]) false;
        ignore @@ dfg#add_vertex @@ mk_proof 2 ty_pr
          (NTTyMap.of_list [((3, ty_pr), false)]) false;
        ignore @@ dfg#add_vertex @@ mk_proof 1 ty_pr
          (NTTyMap.of_list [((2, ty_pr), false)]) false;
        ignore @@ dfg#add_vertex @@ mk_proof 0 ty_pr
          (NTTyMap.of_list [((1, ty_pr), false)]) false;
        (* 0 -> 1 -> 2 -> 3 -> [4 -> 5 -> ...] -> 5 -> 8, 2 -> 9 -> 10, 11
           Note that 4 -> 7 -> 5 branch should be ignored, as it should not be found as start of
           escape path, since it goes back to the cycle.
           Additionally, 9, 10, 11 should not be forgotten just because 2 -> 1, since 2 -> 1
           is not an initial proof.
           We have proofs of 0, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, again 2 and again 5 *)
        let cycle = option_get @@ dfg#find_positive_cycle 0 ty_pr in
        let path_to_cycle, cycle, escape, proofs = cycle#raw_data in
        (* checking cycle *)
        assert_equal ~printer:(Utilities.string_of_list string_of_int)
          [4; 5] @@
        List.sort compare @@ List.map (fun n -> let p = fst n in fst p.derived)
          cycle;
        (* checking path to cycle *)
        assert_equal ~printer:(Utilities.string_of_list string_of_int)
          [0; 1; 2; 3] @@
        List.sort compare @@ List.map (fun n -> let p = fst n in fst p.derived)
          path_to_cycle;
        assert_equal ~printer:string_of_int 5 @@ fst @@ escape.derived;
        (* checking that all required proofs and only required proofs (i.e., except 7) are
           present *)
        assert_equal ~printer:(Utilities.string_of_list string_of_int)
          [0; 1; 2; 2; 3; 4; 5; 5; 6; 8; 9; 10; 11] @@
        List.sort compare @@ List.map (fun p -> fst @@ p.derived) proofs
      );

    (* leaf proof should replace non-leaf initial proof *)
    "dfg-14" >:: (fun _ ->
        let dfg = new dfg in
        assert_equal None @@ dfg#find_positive_cycle 0 ty_pr;
        assert_equal false @@ dfg#add_vertex @@
        mk_proof 2 ty_np empty_used_nts false;
        assert_equal None @@ dfg#find_positive_cycle 0 ty_pr;
        assert_equal true @@ dfg#add_vertex @@
        mk_proof 1 ty_np (nt_ty_used_once 2 ty_np) false;
        assert_equal None @@ dfg#find_positive_cycle 0 ty_pr;
        assert_equal true @@ dfg#add_vertex @@
        mk_proof 0 ty_pr (nt_ty_used_once 1 ty_np) true;
        assert_equal None @@ dfg#find_positive_cycle 0 ty_pr;
        assert_equal true @@ dfg#add_vertex @@
        mk_proof 0 ty_pr (nt_ty_used_once 0 ty_pr) true;
        let cycle1 = option_get @@ dfg#find_positive_cycle 0 ty_pr in
        assert_equal false @@ dfg#add_vertex @@
        mk_proof 1 ty_np empty_used_nts false;
        let cycle2 = option_get @@ dfg#find_positive_cycle 0 ty_pr in
        let path_to_cycle, cycle, escape, proofs = cycle1#raw_data in
        assert_equal ~printer:(Utilities.string_of_list string_of_int)
          [0] @@
        List.sort compare @@ List.map (fun n -> let p = fst n in fst p.derived)
          cycle;
        assert_equal ~printer:(Utilities.string_of_list string_of_int)
          [] @@
        List.sort compare @@ List.map (fun n -> let p = fst n in fst p.derived)
          path_to_cycle;
        assert_equal ~printer:string_of_int 0 @@ fst @@ escape.derived;
        assert_equal ~printer:(Utilities.string_of_list string_of_int)
          [0; 0; 1; 2] @@
        List.sort compare @@ List.map (fun p -> fst @@ p.derived) proofs;
        let path_to_cycle, cycle, escape, proofs = cycle2#raw_data in
        assert_equal ~printer:(Utilities.string_of_list string_of_int)
          [0] @@
        List.sort compare @@ List.map (fun n -> let p = fst n in fst p.derived)
          cycle;
        assert_equal ~printer:(Utilities.string_of_list string_of_int)
          [] @@
        List.sort compare @@ List.map (fun n -> let p = fst n in fst p.derived)
          path_to_cycle;
        assert_equal ~printer:string_of_int 0 @@ fst @@ escape.derived;
        assert_equal ~printer:(Utilities.string_of_list string_of_int)
          [0; 0; 1] @@
        List.sort compare @@ List.map (fun p -> fst @@ p.derived) proofs
      );
  ]



let conversion_test () : test =
  (* These preterminals are defined in a way so that they should be converted to respective
     terminals from paper without creating additional terms (such as functions). *)
  let preserved_preterminals = [
    Syntax.Terminal ("a_", 1, true, false);
    Syntax.Terminal ("b_", 2, false, false);
    Syntax.Terminal ("e_", 0, false, false);
    Syntax.Terminal ("t_", 2, false, true);
    Syntax.Terminal ("id", 1, false, false)
  ] in
  (* This grammar is used to test all combinations of applications of custom terminals
     identical to a, b, e, t with all possible numbers of applied arguments.
     It also tests that not counted terminal with one child is removed when it has an
     argument (as it is identity). *)
  let test_terminals_prerules = [
    ("E", [], Syntax.PApp (Syntax.Name "e_", []));
    ("A", ["x"], Syntax.PApp (Syntax.Name "a_", [
         Syntax.PApp (Syntax.Name "x", [])
       ]));
    ("B", [], Syntax.PApp (Syntax.Name "b_", []));
    ("Be", [], Syntax.PApp (Syntax.Name "b_", [
         Syntax.PApp (Syntax.Name "e_", [])
       ]));
    ("BAee", [], Syntax.PApp (Syntax.Name "b_", [
         Syntax.PApp (Syntax.Name "a_", [Syntax.PApp (Syntax.Name "e_", [])]);
         Syntax.PApp (Syntax.Name "e_", [])
       ]));
    ("X", ["x"], Syntax.PApp (Syntax.Name "x", [
         Syntax.PApp (Syntax.Name "e_", [])
       ]));
    ("Xa", [], Syntax.PApp (Syntax.NT "X", [
         Syntax.PApp (Syntax.Name "a_", [])
       ]));
    ("IDe", [], Syntax.PApp (Syntax.Name "id", [
         Syntax.PApp (Syntax.Name "e_", [])
       ]));
    ("ID", [], Syntax.PApp (Syntax.Name "id", []));
    ("BR", [], Syntax.PApp (Syntax.Name "b_", []));
    ("BRe", [], Syntax.PApp (Syntax.Name "b_", [
         Syntax.PApp (Syntax.Name "e_", [])
       ]));
    ("TRee", [], Syntax.PApp (Syntax.Name "t_", [
         Syntax.PApp (Syntax.Name "e_", []);
         Syntax.PApp (Syntax.Name "e_", [])
       ]));
    ("BRxy", ["x"; "y"], Syntax.PApp (Syntax.Name "b_", [
         Syntax.PApp (Syntax.Name "x", []);
         Syntax.PApp (Syntax.Name "y", [])
       ]))
  ] in
  let t_gram = Conversion.prerules2gram (test_terminals_prerules, preserved_preterminals) in
  print_verbose !Flags.verbose_preprocessing @@ lazy (
    "Basic-like terminals test grammar:\n" ^ t_gram#grammar_info ^ "\n"
  );
  (* This grammar is used to test function conversion. *)
  let f_prerules = [
    ("E", [], Syntax.PApp (Syntax.Name "e", []));
    ("F", ["x"; "y"], Syntax.PApp (
        Syntax.Fun (["p"; "q"], Syntax.PApp (Syntax.Name "p", [
            Syntax.PApp (Syntax.Name "y", [])
          ])),
        [
          Syntax.PApp (Syntax.Name "x", [])
        ]))
  ] in
  let f_gram = Conversion.prerules2gram (f_prerules, []) in
  print_verbose !Flags.verbose_preprocessing @@ lazy (
    "Fun test grammar:\n" ^ t_gram#grammar_info ^ "\n"
  );
  (* This grammar is used to test custom terminals that are not preserved as one of default
     terminals. *)
  let c_preterminals = [
    Syntax.Terminal ("attt", 3, true, true);
    Syntax.Terminal ("ttt", 3, false, true);
    Syntax.Terminal ("bbbb", 4, false, false);
    Syntax.Terminal ("ae", 0, true, true);
    Syntax.Terminal ("auniv", 1, true, true);
  ] in
  let c_prerules = [
    ("ATTT", [], Syntax.PApp (Syntax.Name "attt", []));
    ("TTT", [], Syntax.PApp (Syntax.Name "ttt", []));
    ("BBBB", [], Syntax.PApp (Syntax.Name "bbbb", []));
    ("AE", [], Syntax.PApp (Syntax.Name "ae", []));
    ("AU", [], Syntax.PApp (Syntax.Name "auniv", []))
  ] in
  let c_gram = Conversion.prerules2gram (c_prerules, c_preterminals) in
  print_verbose !Flags.verbose_preprocessing @@ lazy (
    "Custom terminals test grammar:\n" ^ c_gram#grammar_info ^ "\n"
  );
  (* This grammar is used to test function variable scopes. *)
  let s_prerules = [
    (* F -> (fun x -> fun x -> fun x -> x) e e e *)
    ("F", [], Syntax.PApp (
        Syntax.Fun (["x"], Syntax.PApp (
            Syntax.Fun (["x"], Syntax.PApp (
                Syntax.Fun (["x"], Syntax.PApp (
                    Syntax.Name "x", []
                  )),
                [])),
            [])),
        [Syntax.PApp (Syntax.Name "e", []);
         Syntax.PApp (Syntax.Name "e", []);
         Syntax.PApp (Syntax.Name "e", [])]
      ))
  ] in
  let s_gram = Conversion.prerules2gram (s_prerules, []) in
  print_verbose !Flags.verbose_preprocessing @@ lazy (
    "Function scope test grammar:\n" ^ s_gram#grammar_info ^ "\n"
  );
  "conversion" >::: [
    (* Terminals a, b, e, t should be preserved without needless conversion. Therefore, there
       should be no functions apart from the one from identity without arguments, i.e.,
       exactly one extra rule. *)
    "prerules2gram-t1" >:: (fun _ ->
        assert_equal ~printer:string_of_int 14 @@
        Array.length t_gram#rules
      );

    (* Checking that number of leaf terms is correct - nothing extra was added or removed
       aside from extra rule from identity without arguments. *)
    "prerules2gram-t2" >:: (fun _ ->
        assert_equal ~printer:string_of_int 26
        t_gram#size
      );

    "prerules2gram-t3" >:: (fun _ ->
        assert_equal (TE T) @@
        term_head @@ snd @@ t_gram#rules.(t_gram#nt_with_name "TRee")
      );

    "prerules2gram-t4" >:: (fun _ ->
        assert_equal (TE B) @@
        term_head @@ snd @@ t_gram#rules.(t_gram#nt_with_name "BRxy")
      );

    "prerules2gram-t5" >:: (fun _ ->
        assert_equal (NT (t_gram#nt_count - 1)) @@
        term_head @@ snd @@ t_gram#rules.(t_gram#nt_with_name "ID")
      );

    (* Testing that only used part of closure and all variables are in arguments *)
    "prerules2gram-f1" >:: (fun _ ->
        let f_nt : nt_id = f_gram#nt_count - 1 in
        let arity = fst @@ f_gram#rules.(f_nt) in
        assert_equal ["y"; "p"; "q"] @@
        List.map (fun i -> f_gram#var_name (f_nt, i)) @@ range 0 arity
      );

    (* Checking that fun application was converted to _fun0 y x. *)
    "prerules2gram-f2" >:: (fun _ ->
        let f_nt : nt_id = f_gram#nt_count - 1 in
        assert_equal (2, App (
            App (
              NT f_nt,
              Var (f_gram#nt_with_name "F", 1)
            ),
            Var (f_gram#nt_with_name "F", 0)
          )) @@
        f_gram#rules.(f_gram#nt_with_name "F")
      );

    "prerules2gram-c1" >:: (fun _ ->
        assert_equal ~printer:string_of_int 8 @@
        Array.length c_gram#rules
      );

    "prerules2gram-c2" >:: (fun _ ->
        match c_gram#rules.(c_gram#nt_with_name "ATTT") with
        | 0, NT nt ->
          let rule = c_gram#rules.(nt) in
          assert_equal (3, 6, TE A) @@
          (fst @@ rule, size_of_rule rule, term_head @@ snd rule)
        | _, _ -> assert_failure "wrong conversion"
      );

    "prerules2gram-c3" >:: (fun _ ->
        match c_gram#rules.(c_gram#nt_with_name "TTT") with
        | 0, NT nt ->
          let rule = c_gram#rules.(nt) in
          assert_equal (3, 5, TE T) @@
          (fst @@ rule, size_of_rule rule, term_head @@ snd rule)
        | _, _ -> assert_failure "wrong conversion"
      );

    "prerules2gram-c4" >:: (fun _ ->
        match c_gram#rules.(c_gram#nt_with_name "BBBB") with
        | 0, NT nt ->
          let rule = c_gram#rules.(nt) in
          assert_equal (4, 7, TE B) @@
          (fst @@ rule, size_of_rule rule, term_head @@ snd rule)
        | _, _ -> assert_failure "wrong conversion"
      );

    "prerules2gram-c5" >:: (fun _ ->
        assert_equal (0, App (TE A, TE E)) @@
        c_gram#rules.(c_gram#nt_with_name "AE")
      );

    "prerules2gram-c6" >:: (fun _ ->
        assert_equal (0, TE A) @@
        c_gram#rules.(c_gram#nt_with_name "AU")
      );

    (* Three nested functions convert to three new nonterminals. *)
    "prerules2gram-s1" >:: (fun _ ->
        assert_equal ~printer:string_of_int 4 @@
        Array.length s_gram#rules
      );

    (* Since each function shadows x from closure, none of them should take a variable from
       closure into nonterminal definition. *)
    "prerules2gram-s2" >:: (fun _ ->
        assert_equal [0; 1; 1; 1] @@
        List.map fst @@ Array.to_list s_gram#rules
      );

    (* Inner function should use its own x. *)
    "prerules2gram-s3" >:: (fun _ ->
        assert_equal (Var (3, 0)) @@
        snd @@ s_gram#rules.(3)
      );
  ]



let type_test () : test =
  "type" >::: [
    "string_of_ty-1" >:: (fun _ ->
        assert_equal ~printer:id "pr" @@ string_of_ty ty_pr
      );

    "string_of_ty-2" >:: (fun _ ->
        assert_equal ~printer:id "np -> pr" @@
        string_of_ty @@ mk_fun [ity_np] true
      );

    "string_of_ty-3" >:: (fun _ ->
        assert_equal ~printer:id "(np -> pr) -> np" @@
        string_of_ty @@ mk_fun [sty (mk_fun [ity_np] true)] false
      );

    "string_of_ty-4" >:: (fun _ ->
        assert_equal ~printer:id "np /\\ pr -> pr" @@
        string_of_ty @@ mk_fun [TyList.of_list [ty_pr; ty_np]] true
      );

    "string_of_ty-5" >:: (fun _ ->
        assert_equal ~printer:id "T -> pr" @@
        string_of_ty @@ mk_fun [ity_top] true
      );

    "string_of_ty-6" >:: (fun _ ->
        assert_equal ~printer:id "(pr -> pr) -> (np -> pr) -> np -> pr" @@
        string_of_ty @@
        mk_fun [sty @@ mk_fun [ity_pr] true; sty @@ mk_fun [ity_np] true; ity_np] true
      );

    "string_of_ity-1" >:: (fun _ ->
        let s = string_of_ity (TyList.of_list [mk_fun [ity_pr] true; mk_fun [ity_np] false]) in
        assert_equal true @@ (s = "(pr -> pr) /\\ (np -> np)" || s = "(np -> np) /\\ (pr -> pr)")
      );
    
    "ty_of_string-1" >:: (fun _ ->
        assert_equal ~cmp:Ty.equal ty_pr @@ ty_of_string "pr"
      );

    "ty_of_string-2" >:: (fun _ ->
        assert_equal ~cmp:Ty.equal (mk_fun [ity_np] true) @@ ty_of_string "np -> pr"
      );

    "ty_of_string-3" >:: (fun _ ->
        assert_equal ~cmp:Ty.equal (mk_fun [sty @@ mk_fun [ity_np] true] false) @@
        ty_of_string "(np -> pr) -> np"
      );

    "ty_of_string-4" >:: (fun _ ->
        assert_equal ~cmp:Ty.equal (mk_fun [TyList.of_list [ty_np; ty_pr]] true) @@
        ty_of_string "pr /\\ np -> pr"
      );

    "ty_of_string-5" >:: (fun _ ->
        assert_equal ~cmp:Ty.equal (mk_fun [ity_top] true) @@
        ty_of_string "T -> pr"
      );

    "ty_of_string-6" >:: (fun _ ->
        assert_equal ~cmp:Ty.equal
          (mk_fun [sty @@ mk_fun [ity_pr] true; sty @@ mk_fun [ity_np] true; ity_np] true) @@
        ty_of_string "(pr -> pr) -> (np -> pr) -> np -> pr"
      );

    "ity_of_string-1" >:: (fun _ ->
        assert_equal ~cmp:TyList.equal
          (TyList.of_list [mk_fun [ity_pr] true; mk_fun [ity_np] false]) @@
        ity_of_string "(pr -> pr) /\\ (np -> np)"
      );
  ]


let te_test () : test =
  "targetEnvms" >::: [
    (* basic case *)
    "intersect-1" >:: (fun _ ->
        assert_equal_tes
          (TargetEnvs.singleton_empty_meta ty_np [] empty_ctx) @@
        TargetEnvs.intersect
          (TargetEnvs.singleton_empty_meta ty_np [] empty_ctx)
          (TargetEnvs.singleton_empty_meta ty_np [] empty_ctx)
      );

    (* pr variable duplication creates duplication flag *)
    "intersect-2" >:: (fun _ ->
        assert_equal_tes
          (TargetEnvs.singleton_of_env ty_np
             (with_dup true @@
              singleton_env empty_used_nts empty_loc_types true (0, 0) @@ sty ty_pr)
             empty_ctx) @@
        TargetEnvs.intersect
          (TargetEnvs.singleton_empty_meta ty_np [(0, sty ty_pr)] empty_ctx)
          (TargetEnvs.singleton_empty_meta ty_np [(0, sty ty_pr)] empty_ctx)
      );

    (* np variable duplication does not create duplication flag *)
    "intersect-3" >:: (fun _ ->
        assert_equal_tes
          (TargetEnvs.singleton_of_env ty_np
             (singleton_env empty_used_nts empty_loc_types false (0, 0) @@ sty ty_np)
             empty_ctx) @@
        TargetEnvs.intersect
          (TargetEnvs.singleton_empty_meta ty_np [(0, sty ty_np)] empty_ctx)
          (TargetEnvs.singleton_empty_meta ty_np [(0, sty ty_np)] empty_ctx)
      );

    (* Idempotent merging with respect to positivity, merging of nonterminals, dropping ty_pr
       target that did not appear in both parts of intersection. *)
    "intersect-4" >:: (fun _ ->
        assert_equal_tes
          (let used_nts =
             NTTyMap.of_list [
               ((0, ty_pr), false);
               ((0, ty_np), false)
             ] in
           TargetEnvs.singleton_of_env ty_np
             (singleton_env used_nts empty_loc_types true (0, 0) @@ sty ty_np) empty_ctx) @@
        TargetEnvs.intersect
          (TargetEnvs.singleton_of_env ty_np
             (singleton_env (nt_ty_used_once 0 ty_pr) empty_loc_types true
                (0, 0) @@ sty ty_np) empty_ctx)
          (TargetEnvs.of_list [
              (ty_np, [
                  (singleton_env (nt_ty_used_once 0 ty_np) empty_loc_types true
                     (0, 0) @@ sty ty_np, empty_ctx);
                  (singleton_env (nt_ty_used_once 0 ty_np) empty_loc_types false
                     (0, 0) @@ sty ty_np, empty_ctx)]);
              (ty_pr, [
                  (singleton_env empty_used_nts empty_loc_types false
                     (0, 0) @@ sty ty_np, empty_ctx)])
            ])
      );

    (* Merging two same nonterminal typings, merging false positivity with both ones,
       discarding different target. *)
    "intersect-5" >:: (fun _ ->
        assert_equal_tes
          (TargetEnvs.of_list [
              (ty_np, [
                  (singleton_env (NTTyMap.singleton (0, ty_np) true) empty_loc_types false
                     (0, 0) @@ sty ty_np, empty_ctx);
                  (singleton_env (NTTyMap.singleton (0, ty_np) true) empty_loc_types true
                     (0, 0) @@ sty ty_np, empty_ctx)])]) @@
        TargetEnvs.intersect
          (TargetEnvs.singleton_of_env ty_np
             (singleton_env (nt_ty_used_once 0 ty_np) empty_loc_types false
                (0, 0) @@ sty ty_np) empty_ctx)
          (TargetEnvs.of_list [
              (ty_np, [
                  (singleton_env (nt_ty_used_once 0 ty_np) empty_loc_types true
                     (0, 0) @@ sty ty_np, empty_ctx);
                  (singleton_env (nt_ty_used_once 0 ty_np) empty_loc_types false
                     (0, 0) @@ sty ty_np, empty_ctx)]);
              (ty_pr, [
                  (singleton_env empty_used_nts empty_loc_types false
                     (0, 0) @@ sty ty_np, empty_ctx)])
            ])
      );

    (* Merging different variables with same context. *)
    "intersect-6" >:: (fun _ ->
        assert_equal_tes
          (TargetEnvs.of_list [
              (ty_np, [
                  (singleton_env empty_used_nts empty_loc_types false
                     (0, 0) @@ ity_of_string "pr /\\ np", empty_ctx);
                  (singleton_env empty_used_nts empty_loc_types false
                     (0, 1) @@ ity_of_string "pr /\\ np", empty_ctx);
                  (mk_env empty_used_nts empty_loc_types false @@ IntMap.of_list
                     [(0, sty ty_np); (1, sty ty_pr)], empty_ctx);
                  (mk_env empty_used_nts empty_loc_types false @@ IntMap.of_list
                     [(0, sty ty_pr); (1, sty ty_np)], empty_ctx)
                ])
            ]) @@
        TargetEnvs.intersect
          (TargetEnvs.of_list [
              (ty_np, [
                  (singleton_env empty_used_nts empty_loc_types false
                     (0, 0) @@ sty ty_np, empty_ctx)]);
              (ty_np, [
                  (singleton_env empty_used_nts empty_loc_types false
                     (0, 1) @@ sty ty_np, empty_ctx)])
            ])
          (TargetEnvs.of_list [
              (ty_np, [
                   (singleton_env empty_used_nts empty_loc_types false
                     (0, 0) @@ sty ty_pr, empty_ctx)]);
              (ty_np, [
                  (singleton_env empty_used_nts empty_loc_types false
                     (0, 1) @@ sty ty_pr, empty_ctx)])
            ])
      );
    
    (* Merging different variables with different contexts. *)
    "intersect-7" >:: (fun _ ->
        let ctx1 =
          lctx [(0, (0, 0)); (1, (1, 0))]
            [(0, [[sty ty_pr]]); (1, [[sty ty_np]; [sty ty_pr]])]
            None None
        in
        let ctx2 =
          lctx [(0, (0, 0)); (1, (1, 0))]
            [(0, [[sty ty_np]; [sty ty_pr]]); (1, [[sty ty_np]])]
            None None
        in
        let ctx12 =
          lctx [(0, (0, 0)); (1, (1, 0))]
            [(0, [[sty ty_pr]]); (1, [[sty ty_np]])]
            None None
        in
        assert_equal_tes
          (TargetEnvs.of_list [
              (ty_np, [
                  (singleton_env empty_used_nts empty_loc_types false
                     (0, 0) @@ ity_of_string "pr /\\ np", ctx1);
                  (singleton_env empty_used_nts empty_loc_types false
                     (0, 1) @@ ity_of_string "pr /\\ np", ctx12);
                  (mk_env empty_used_nts empty_loc_types false @@ IntMap.of_list
                     [(0, sty ty_np); (1, sty ty_pr)], ctx12);
                  (mk_env empty_used_nts empty_loc_types false @@ IntMap.of_list
                     [(0, sty ty_pr); (1, sty ty_np)], ctx1)
                ])
            ]) @@
        TargetEnvs.intersect
          (TargetEnvs.of_list [
              (ty_np, [
                  (singleton_env empty_used_nts empty_loc_types false
                     (0, 0) @@ sty ty_np, ctx1)]);
              (ty_np, [
                  (singleton_env empty_used_nts empty_loc_types false
                     (0, 1) @@ sty ty_np, ctx1)])
            ])
          (TargetEnvs.of_list [
              (ty_np, [
                   (singleton_env empty_used_nts empty_loc_types false
                     (0, 0) @@ sty ty_pr, ctx1)]);
              (ty_np, [
                  (singleton_env empty_used_nts empty_loc_types false
                     (0, 1) @@ sty ty_pr, ctx2)])
            ])
      );

    (* Merging different variables and context of out which some are incompatible. *)
    "intersect-8" >:: (fun _ ->
        let ity_np_pr = TyList.of_list [ty_np; ty_pr] in
        let ctx1 =
          lctx [(0, (0, 0)); (1, (0, 1))]
            [(0, [[ity_np_pr; sty ty_np]])]
            None None
        in
        let ctx2 =
          lctx [(0, (0, 0)); (1, (0, 1))]
            [(0, [[ity_np_pr; sty ty_pr]])]
            None None
        in
        assert_equal_tes
          (TargetEnvs.of_list [
              (ty_np, [
                  (singleton_env empty_used_nts empty_loc_types false
                     (0, 0) @@ ity_of_string "pr /\\ np", ctx1);
                  (mk_env empty_used_nts empty_loc_types false @@ IntMap.of_list
                     [(0, sty ty_pr); (1, sty ty_np)], ctx1)
                ])
            ]) @@
        TargetEnvs.intersect
          (TargetEnvs.of_list [
              (ty_np, [
                  (singleton_env empty_used_nts empty_loc_types false
                     (0, 0) @@ sty ty_np, ctx1)]);
              (ty_np, [
                  (singleton_env empty_used_nts empty_loc_types false
                     (0, 1) @@ sty ty_np, ctx1)])
            ])
          (TargetEnvs.of_list [
              (ty_np, [
                   (singleton_env empty_used_nts empty_loc_types false
                     (0, 0) @@ sty ty_pr, ctx1)]);
              (ty_np, [
                  (singleton_env empty_used_nts empty_loc_types false
                     (0, 1) @@ sty ty_pr, ctx2)])
            ])
      );

    "size-1" >:: (fun _ ->
        assert_equal ~printer:string_of_int 1 @@
        TargetEnvs.size @@
        TargetEnvs.singleton_empty_meta ty_np [] empty_ctx
      );
  ]



(** The smallest possible grammar. *)
let grammar_e () = mk_grammar
    [|
      (0, TE E) (* N0 -> e *)
    |]

let typing_e_test () =
  let hg, typing = mk_typing @@ grammar_e () in
  [
    (* check if e : np type checks *)
    "type_check-e-1" >:: (fun _ ->
        assert_equal_tes
          (TargetEnvs.singleton_empty_meta ty_np [] empty_ctx) @@
        type_check_nt_wo_ctx typing hg 0 ty_np false false
      );

    (* checking basic functionality of forcing pr vars *)
    "type_check-e-2" >:: (fun _ ->
        assert_equal_tes
          TargetEnvs.empty @@
        type_check_nt_wo_ctx typing hg 0 ty_np false true
      );

    (* checking that forcing no pr vars does not break anything when there are only terminals *)
    "type_check-e-3" >:: (fun _ ->
        assert_equal_tes
          (TargetEnvs.singleton_empty_meta ty_np [] empty_ctx) @@
        type_check_nt_wo_ctx typing hg 0 ty_np true false
      );

    (* with forcing nt ty *)
    "type_check-e-4" >:: (fun _ ->
        (* the location is outside, which is normal for sub-terms *)
        let ctx = {
          empty_ctx with
          forced_nt_ty = Some (HlocSet.singleton 42, TySet.singleton ty_np)
        } in
        assert_equal_tes
          TargetEnvs.empty @@
        typing#type_check (hg#nt_body 0) None ctx true false
      );    
  ]



(** Grammar that tests usage of a variable. *)
let grammar_ax () = mk_grammar
    [|
      (0, App (NT 1, TE E)); (* N0 -> N1 e *)
      (1, App (TE A, Var (1, 0))) (* N1 x -> a x *)
    |]

let typing_ax_test () =
  let hg, typing = mk_typing @@ grammar_ax () in
  let ctx = sctx typing ["pr /\\ np"] in
  [
    (* check that a x : pr accepts both productivities of x *)
    "type_check-a-1" >:: (fun _ ->
        assert_equal_tes
          (TargetEnvs.of_list [
              (ty_pr, [
                  (senv true 0 "pr", sctx typing ["np /\\ pr"]);
                  (senv true 0 "np", sctx typing ["np /\\ pr"])
                ])
            ]) @@
        type_check_nt typing hg 1 ty_pr ctx false false
      );

    (* check that a x : np does not type check *)
    "type_check-a-2" >:: (fun _ ->
        assert_equal_tes
          TargetEnvs.empty @@
        type_check_nt typing hg 1 ty_np ctx false false
      );
  ]



(** Grammar that tests intersection - x and y are inferred from one argument in N1 rule, and y and
    z from the other. N4 tests top. *)
let grammar_xyyz () = mk_grammar
    [|
      (* N0 -> N1 a N4 e *)
      (0, App (App (App (NT 1, TE A), NT 4), TE E));
      (* N1 x y z -> N2 x y (N3 y z) *)
      (3, App (
          App (App (NT 2, Var (1, 0)), Var (1, 1)),
          App (App (NT 3, Var (1, 1)), Var (1, 2))
        ));
      (* N2 x y v -> x (y v) *)
      (3, App (Var (2, 0), App (Var (2, 1), Var (2, 2))));
      (* N3 y z -> y z *)
      (2, App (Var (3, 0), Var (3, 1)));
      (* N4 x -> b (a x) x *)
      (1, App (App (TE B, App (TE A, Var (4, 0))), Var (4, 0)));
      (* N5 -> N5 *)
      (0, NT 5)
    |]

let typing_xyyz_test () =
  let hg, typing = mk_typing @@ grammar_xyyz () in
  ignore @@ typing#add_nt_ty 2 @@ ty_of_string "(pr -> pr) -> (np -> pr) -> np -> pr";
  ignore @@ typing#add_nt_ty 3 @@ ty_of_string "(np -> np) -> np -> np";
  let id0_0 = hg#locate_hterms_id 0 [0] in
  ignore @@ typing#get_hty_store#add_hty id0_0
    [|
      TySet.of_string "pr -> pr";
      TySet.of_string "np -> np";
      TySet.of_string "np -> pr"
    |];
  ignore @@ typing#get_hty_store#add_hty id0_0
    [|
      TySet.of_string "pr -> pr";
      TySet.of_string "pr -> pr";
      TySet.of_string "pr -> pr"
    |];
  let binding1 = [(0, 2, id0_0)] in
  let var_bix1 = [(0, (0, 0)); (1, (0, 1)); (2, (0, 2))] in
  [
    (* check that intersection of common types from different arguments works *)
    "type_check-x-1" >:: (fun _ ->
        let used_nts =
          NTTyMap.of_list [
            ((2, ty_of_string "(pr -> pr) -> (np -> pr) -> np -> pr"), false);
            ((3, ty_of_string "(np -> np) -> np -> np"), false)
          ]
        in
        assert_equal_tes
          (TargetEnvs.of_list [
              (ty_pr, [
                  (mk_env used_nts empty_loc_types false @@ IntMap.of_list @@ index_list @@ [
                      ity_of_string "pr -> pr";
                      ity_of_string "(np -> pr) /\\ (np -> np)";
                      ity_of_string "np"
                    ], empty_ctx)
                ])
            ]) @@
        type_check_nt_wo_ctx typing hg 1 ty_pr false false
      );

    (* check that branching works *)
    "type_check-x-2" >:: (fun _ ->
        assert_equal_tes
          (TargetEnvs.of_list [
              (ty_pr, [
                  (senv true 0 "np", empty_ctx);
                  (senv true 0 "pr", empty_ctx)
                ])
            ]) @@
        type_check_nt_wo_ctx typing hg 4 ty_pr false false
      );

    (* check that branching works *)
    "type_check-x-3" >:: (fun _ ->
        assert_equal_tes
          (TargetEnvs.of_list [
              (ty_np, [
                  (senv false 0 "np", empty_ctx);
                  (senv false 0 "pr", empty_ctx)
                ])
            ]) @@
        type_check_nt_wo_ctx typing hg 4 ty_np false false
      );

    (* Basic creation of context without a product *)
    "binding2ctx-1" >:: (fun _ ->
        let bix_htys =
          [(0, [
              [
                ity_of_string "pr -> pr";
                ity_of_string "pr -> pr";
                ity_of_string "pr -> pr"
              ]; [
                ity_of_string "pr -> pr";
                ity_of_string "np -> np";
                ity_of_string "np -> pr"
              ]
            ])]
        in
        assert_equal_ctxs
          (lctx var_bix1 bix_htys None None) @@
        typing#binding2ctx (hg#nt_body 1) None None None binding1
      );

    (* Basic creation of context with mask without all but first variables, without product *)
    "binding2ctx-2" >:: (fun _ ->
        let bix_htys =
          [(0, [
              [
                ity_of_string "pr -> pr";
                ity_of_string "T";
                ity_of_string "T"
              ]
            ])]
        in
        assert_equal_ctxs
          (lctx var_bix1 bix_htys None None) @@
        typing#binding2ctx (hg#nt_body 1) (Some (SortedVars.of_list [(0, 0)])) None None
          binding1
      );

    (* Creation of context with mask and fixed hty of hterms. *)
    "binding2ctx-3" >:: (fun _ ->
        let bix_htys = [
          (0, [
              [
                ity_top;
                ity_top;
                ity_of_string "np -> pr"
              ]
            ])
        ] in
        let forced_hterms_hty =
          Some [(0, [|tys_top; tys_top; TySet.of_string "np -> pr"|])]
        in
        assert_equal_ctxs
          (lctx var_bix1 bix_htys forced_hterms_hty None) @@
        typing#binding2ctx (hg#nt_body 1) (Some (SortedVars.of_list [(1, 2)]))
          (Some (id0_0, [|tys_top; tys_top; TySet.of_string "np -> pr"|]))
          None
          binding1
      );
  ]



(** Grammar that tests typing with duplication in N1 when N2 receives two the same arguments. It
    also tests no duplication when these arguments are different in N3. It also has a binding
    where N4 is partially applied, so it has two elements from two different nonterminals. *)
let grammar_dup () = mk_grammar
    [|
      (* N0 -> b (b (N1 a) (N3 a a)) (N5 N4 (a e)) *)
      (0, App (App (
           TE B,
           App (App (
               TE B,
               App (NT 2, TE A)),
                App (App (NT 3, TE A), App (TE A, TE E)))),
               App (App (NT 5, NT 4), App (TE A, TE E))));
      (* N1 x y z -> x (y z) *)
      (3, App (Var (1, 0), App  (Var (1, 1), Var (1, 2))));
      (* N2 x -> N1 x x (a e) *)
      (1, App (App (App (NT 1, Var (2, 0)), Var (2, 0)), App (TE A, TE E)));
      (* N3 x y -> N1 x x y *)
      (2, App (App (App (NT 1, Var (3, 0)), Var (3, 0)), Var (3, 1)));
      (* N4 x y z -> N1 x y z *)
      (3, App (App (App (NT 1, Var (4, 0)), Var (4, 1)), Var (4, 2)));
      (* N5 x -> N6 (x a) *)
      (1, App (NT 6, App (Var (5, 0), TE A)));
      (* N6 x -> x a *)
      (1, App (Var (6, 0), TE A))
    |]

let typing_dup_test () =
  let hg, typing = mk_typing @@ grammar_dup () in
  ignore @@ typing#add_nt_ty 1 @@ ty_of_string "(pr -> pr) -> (pr -> pr) -> pr -> np";
  ignore @@ typing#add_nt_ty 1 @@ ty_of_string "(pr -> np) -> (pr -> np) -> pr -> np";
  [
    (* All valid typings of x type check, because the application is already productive due to
       a e being productive. *)
    "type_check-d-1" >:: (fun _ ->
        let used_nts1 = nt_ty_used_once 1 (
            ty_of_string "(pr -> pr) -> (pr -> pr) -> pr -> np")
        in
        let used_nts2 = nt_ty_used_once 1 (
            ty_of_string "(pr -> np) -> (pr -> np) -> pr -> np")
        in
        assert_equal_tes
          (TargetEnvs.of_list [
              (ty_pr, [
                  (mk_env used_nts1 empty_loc_types true @@
                   IntMap.singleton 0 @@ ity_of_string "pr -> pr", empty_ctx);
                  (mk_env used_nts2 empty_loc_types true @@
                   IntMap.singleton 0 @@ ity_of_string "pr -> np", empty_ctx)
                ])
            ]) @@
        type_check_nt_wo_ctx typing hg 2 ty_pr false false
      );

    (* No valid environment, because a e is productive and makes the application with it as
       argument productive. *)
    "type_check-d-2" >:: (fun _ ->
        assert_equal_tes
          TargetEnvs.empty @@
        type_check_nt_wo_ctx typing hg 2 ty_np false false
      );

    (* Only one valid env when there is a duplication. Since everything in N1 is a variable,
       there is no way to create pr terms without a duplication. The x : pr -> pr typing
       causes a duplication and type checks. Typing x : pr -> np does not type check, because
       it is not productive, so it is not a duplication. y : pr is forced by there being no
       known typing of the head with unproductive last argument. *)
    "type_check-d-3" >:: (fun _ ->
        let used_nts =
          nt_ty_used_once 1 (ty_of_string "(pr -> pr) -> (pr -> pr) -> pr -> np")
        in
        assert_equal_tes
          (TargetEnvs.of_list [
              (ty_pr, [
                  (mk_env used_nts empty_loc_types true @@
                   IntMap.of_list @@ index_list @@ [
                     ity_of_string "pr -> pr";
                     ity_of_string "pr"
                   ], empty_ctx)
                ])
            ]) @@
        type_check_nt_wo_ctx typing hg 3 ty_pr false false
      );

    (* Only one valid env when there is no duplication. This is exactly the opposite of the test
       above with x : pr -> np passing and x : pr -> pr failing and y : pr being forced. *)
    "type_check-d-4" >:: (fun _ ->
        let used_nts =
          nt_ty_used_once 1 (ty_of_string "(pr -> np) -> (pr -> np) -> pr -> np")
        in
        assert_equal_tes
          (TargetEnvs.of_list [
              (ty_np, [
                  (mk_env used_nts empty_loc_types false @@
                   IntMap.of_list @@ index_list @@ [
                     ity_of_string "pr -> np";
                     ity_of_string "pr"
                   ], empty_ctx)
                ])
            ]) @@
        type_check_nt_wo_ctx typing hg 3 ty_np false false
      );

    (* Similar to test 11, but this time there are separate variables used for first
       and second argument, so there is no place for duplication. This means that there is no
       way to achieve productivity. *)
    "type_check-d-5" >:: (fun _ ->
        assert_equal_tes
          TargetEnvs.empty @@
        type_check_nt_wo_ctx typing hg 4 ty_pr false false
      );

    (* Similar to test 12, but this time the duplication cannot happen. *)
    "type_check-d-6" >:: (fun _ ->
        let used_nts1 =
          nt_ty_used_once 1 (ty_of_string "(pr -> pr) -> (pr -> pr) -> pr -> np")
        in
        let used_nts2 =
          nt_ty_used_once 1 (ty_of_string "(pr -> np) -> (pr -> np) -> pr -> np")
        in
        assert_equal_tes
          (TargetEnvs.of_list @@ [
              (ty_np, [
                  (mk_env used_nts1 empty_loc_types false @@
                   IntMap.of_list @@ index_list @@ [
                     ity_of_string "pr -> pr";
                     ity_of_string "pr -> pr";
                     ity_of_string "pr"
                   ], empty_ctx);
                  (mk_env used_nts2 empty_loc_types false @@
                   IntMap.of_list @@ index_list @@ [
                     ity_of_string "pr -> np";
                     ity_of_string "pr -> np";
                     ity_of_string "pr"
                   ], empty_ctx)
                ])
            ]) @@
        type_check_nt_wo_ctx typing hg 4 ty_np false false
      );

    (* Typing without target *)
    "type_check-d-7" >:: (fun _ ->
        let used_nts1 =
          nt_ty_used_once 1 (ty_of_string "(pr -> pr) -> (pr -> pr) -> pr -> np")
        in
        let used_nts2 =
          nt_ty_used_once 1 (ty_of_string "(pr -> np) -> (pr -> np) -> pr -> np")
        in
        assert_equal_tes
          (TargetEnvs.of_list @@ [
              (ty_pr, [
                  (mk_env used_nts1 empty_loc_types true @@
                   IntMap.of_list @@ index_list @@ [
                     ity_of_string "pr -> pr";
                     ity_of_string "pr"
                   ], empty_ctx)
                ]);
              (ty_np, [
                  (mk_env used_nts2 empty_loc_types false @@
                   IntMap.of_list @@ index_list @@ [
                     ity_of_string "pr -> np";
                     ity_of_string "pr"
                   ], empty_ctx)
                ])
            ]) @@
        type_check_nt_wo_ctx_wo_target typing hg 3 false false
      );

    (* Typing without target, but with forced nonterminal type *)
    "type_check-d-8" >:: (fun _ ->
        let ty = ty_of_string "(pr -> pr) -> (pr -> pr) -> pr -> np" in
        let ctx =
          lctx [(0, (0, 0)); (1, (0, 1))] [
            (0, [[ity_of_string "pr -> pr"; ity_of_string "pr"]])
          ] None @@ Some ([0], TySet.singleton ty)
        in
        assert_equal_tes
          (TargetEnvs.of_list @@ [
              (ty_pr, [
                  (mk_env (nt_ty_used_once 1 ty) empty_loc_types true @@
                   IntMap.of_list @@ index_list @@ [
                     ity_of_string "pr -> pr";
                     ity_of_string "pr"
                   ], { ctx with forced_nt_ty = None })
                ]);
            ]) @@
        typing#type_check_hterm (hg#nt_body 3) None ctx 0 false false
      );
  ]



(** Grammar that has nonterminal that has binding in the form N [t] [t] for the same t. Used
    to test edge cases for bindings. *)
let grammar_double () = mk_grammar
    [|
      (* N0 -> N1 a (b (a e) e) *)
      (0, App (App (NT 1, TE A), App(App(TE B, App(TE A, TE E)), TE E)));
      (* N1 x y -> b (x y) (N1 (N2 y) y)
         0CFA will find binding N1 [N2 y; y] and N0 [a; b (a e) e]. *)
      (2, App (App (
           TE B,
           App (Var (1, 0), Var (1, 1))),
               App (App (NT 1, App (NT 2, Var (1, 1))), Var (1, 1)))
      );
      (* N2 x y -> x
         0CFA will find a binding N2 [y] [y] *)
      (2, Var (2, 0))
    |]

let typing_double_test () =
  let hg, typing = mk_typing @@ grammar_double () in
  let id0_abaee = hg#locate_hterms_id 0 [0] in
  ignore @@ typing#add_hterms_hty id0_abaee @@
  [|TySet.of_string "np -> pr /\\ pr -> pr"; TySet.of_string "pr"|];
  ignore @@ typing#add_hterms_hty id0_abaee @@
  [|TySet.of_string "np -> pr /\\ pr -> pr"; TySet.of_string "np"|];
  let id1_y = hg#locate_hterms_id 1 [0; 0; 0] in
  ignore @@ typing#add_hterms_hty id1_y @@ [|TySet.of_string "pr"|];
  ignore @@ typing#add_hterms_hty id1_y @@ [|TySet.of_string "np"|];
  ignore @@ typing#add_nt_ty 2 @@ ty_of_string "np -> T -> np";
  let var_bix1 = [(0, (0, 0)); (1, (0, 1))] in
  let var_bix2 = [(0, (0, 0)); (1, (1, 0))] in
  [
    (* Creation of context with fixed hty of hterms when there are two copies of
       fixed hterms in a binding and without mask. *)
    "binding2ctx-4" >:: (fun _ ->
        let bix_htys = [
          (0, [[ity_of_string "pr"]; [ity_of_string "np"]]);
          (1, [[ity_of_string "pr"]; [ity_of_string "np"]])
        ] in
        let forced_hterms_hty =
          Some [(0, [|TySet.of_string "pr"|]); (1, [|TySet.of_string "pr"|])]
        in
        assert_equal_ctxs
          (lctx var_bix2 bix_htys forced_hterms_hty None) @@
        typing#binding2ctx (hg#nt_body 2) None (Some (id1_y, [|TySet.of_string "pr"|])) None
          [(0, 0, id1_y); (1, 1, id1_y)]
      );

    (* Creation of context with mask and with fixed hty of hterms when there are
       two copies of fixed hterms in a binding. *)
    "binding2ctx-5" >:: (fun _ ->
        let bix_htys = [
          (0, [[ity_of_string "pr"]; [ity_of_string "np"]]);
          (1, [[ity_of_string "T"]])
        ] in
        let forced_hterms_hty =
          Some [(0, [|TySet.of_string "pr"|]); (1, [|tys_top|])]
        in
        assert_equal_ctxs
          (lctx var_bix2 bix_htys forced_hterms_hty None) @@
        typing#binding2ctx (hg#nt_body 2) (Some (SortedVars.singleton (2, 0)))
          (Some (id1_y, [|TySet.of_string "pr"|])) None [(0, 0, id1_y); (1, 1, id1_y)]
      );

    (* Creation of context without mask or forced hty when there are two copies of same
       hterms in a binding. *)
    "binding2ctx-6" >:: (fun _ ->
        let bix_htys = [
          (0, [[ity_of_string "pr"]; [ity_of_string "np"]]);
          (1, [[ity_of_string "pr"]; [ity_of_string "np"]])
        ] in
        assert_equal_ctxs
          (lctx var_bix2 bix_htys None None) @@
        typing#binding2ctx (hg#nt_body 2) None None None [(0, 0, id1_y); (1, 1, id1_y)]
      );

    (* Creation of context without mask and without fixed hty of hterms. *)
    "binding2ctx-7" >:: (fun _ ->
        let bix_htys = [
          (0, [
              [ity_of_string "pr -> pr /\\ np -> pr"; ity_of_string "pr"];
              [ity_of_string "pr -> pr /\\ np -> pr"; ity_of_string "np"]
            ])
        ] in
        assert_equal_ctxs
          (lctx var_bix1 bix_htys None None) @@
        typing#binding2ctx (hg#nt_body 1) None None None [(0, 1, id0_abaee)]
      );

    (* Creation of context with mask and fixed hty of hterms. Note that effectively this
       will create no fixes htys, since the requirement will be satisfied immidiately
       due to no other choices. *)
    "binding2ctx-8" >:: (fun _ ->
        let bix_htys = [
          (0, [
              [ity_of_string "pr -> pr /\\ np -> pr"; ity_of_string "T"]
            ])
        ] in
        assert_equal_ctxs
          (lctx var_bix1 bix_htys None None) @@
        typing#binding2ctx (hg#nt_body 1)
          (Some (SortedVars.singleton (1, 0)))
          (Some (id0_abaee, [|TySet.of_string "pr -> pr /\\ np -> pr"; TySet.of_string "np"|]))
          None
          [(0, 1, id0_abaee)]
      );

    (* Creation of context with mask and fixed hty of hterms. The requirement will also be
       satisfied right away, but due to constraints. *)
    "binding2ctx-9" >:: (fun _ ->
        let bix_htys = [
          (0, [
              [ity_of_string "T"; ity_of_string "np"]
            ])
        ] in
        assert_equal_ctxs
          (lctx var_bix1 bix_htys None None) @@
        typing#binding2ctx (hg#nt_body 1)
          (Some (SortedVars.singleton (1, 1)))
          (Some (id0_abaee, [|TySet.of_string "pr -> pr /\\ np -> pr"; TySet.of_string "np"|]))
          None
          [(0, 1, id0_abaee)]
      );

    (* Creation of bindings with no variables. *)
    "binding2envms-10" >:: (fun _ ->
        assert_equal_ctxs
          empty_ctx @@
        typing#binding2ctx (hg#nt_body 0) None None None []
      );

    (* Bindings with forced nonterminal *)
    "binding2ctx-11" >:: (fun _ ->
        let bix_htys = [
          (0, [
              [ity_of_string "pr -> pr /\\ np -> pr"; ity_of_string "T"]
            ])
        ] in
        assert_equal_ctxs
          (lctx var_bix1 bix_htys None @@ Some ([4], TySet.of_string "np -> T -> np")) @@
        typing#binding2ctx (hg#nt_body 1)
          (Some (SortedVars.singleton (1, 0)))
          (Some (id0_abaee, [|TySet.of_string "pr -> pr /\\ np -> pr"; TySet.of_string "np"|]))
          (Some (2, TySet.of_string "np -> T -> np"))
          [(0, 1, id0_abaee)]
      );
  ]



(** Grammar to test other features of typing algorithm. *)
let grammar_misc () = mk_grammar
    [|
      (* N0 -> N1 e *)
      (0, App (NT 1, TE E));
      (* N1 x -> a x *)
      (1, App (TE A, Var (1, 0)));
      (* N2 -> N2 *)
      (0, NT 2);
      (* N3 -> N4 N5 N5 e *)
      (0, App (App (App (NT 4, NT 5), NT 5), TE E));
      (* N4 f g x -> f (g x) *)
      (3, App (Var (4, 0), App (Var (4, 1), Var (4, 2))));
      (* N5 x -> x *)
      (1, Var (5, 0))
    |]

let typing_misc_test () =
  let hg, typing = mk_typing @@ grammar_misc () in
  ignore @@ typing#add_nt_ty 4 @@ ty_of_string "(np -> np) -> (np -> np) -> np -> np";
  ignore @@ typing#add_nt_ty 4 @@ ty_of_string "(pr -> pr) -> (np -> pr) -> np -> np";
  ignore @@ typing#add_nt_ty 5 @@ ty_of_string "np -> np";
  ignore @@ typing#add_nt_ty 5 @@ ty_of_string "pr -> np";
  [
    (* Typing a x without target should not yield np target. *)
    "type_check-m-1" >:: (fun _ ->
        let ctx = sctx typing ["pr"] in
        assert_equal_tes
          (TargetEnvs.of_list @@ [
              (ty_pr, [
                  (senv true 0 "pr", ctx)
                ])
            ]) @@
        typing#type_check (hg#nt_body 1) None ctx false false
      );

    (* Typing a x without target should not yield np target. *)
    "type_check-m-2" >:: (fun _ ->
        let ctx = sctx typing ["np"] in
        assert_equal_tes
          (TargetEnvs.of_list @@ [
              (ty_pr, [
                  (senv true 0 "np", ctx)
                ])
            ]
          ) @@
        typing#type_check (hg#nt_body 1) None ctx false false
      );

    (* Typing a x without target should not yield np target. *)
    "type_check-m-3" >:: (fun _ ->
        assert_equal_tes
          (TargetEnvs.of_list @@ [
              (ty_pr, [
                  (senv true 0 "pr", empty_ctx);
                  (senv true 0 "np", empty_ctx)
                ])
            ]) @@
        typing#type_check (hg#nt_body 1) None empty_ctx false false
      );

    (* Typing a x should work for both types of the variable. *)
    "type_check-m-4" >:: (fun _ ->
        assert_equal_tes
          (TargetEnvs.of_list @@ [
              (ty_pr, [
                  (senv true 0 "pr", empty_ctx);
                  (senv true 0 "np", empty_ctx)
                ])
            ]) @@
        typing#type_check (hg#nt_body 1) (Some ty_pr) empty_ctx false false
      );

    (* Can't type a nonterminal with no data on dependencies without target. *)
    "type_check-m-5" >:: (fun _ ->
        assert_equal_tes
          TargetEnvs.empty @@
        typing#type_check (hg#nt_body 2) None empty_ctx false false
      );

    (* Can't type a nonterminal with no data on dependencies with target. *)
    "type_check-m-6" >:: (fun _ ->
        assert_equal_tes
          TargetEnvs.empty @@
        typing#type_check (hg#nt_body 2) (Some ty_np) empty_ctx false false
      );
    
    (* Typing identity should work for both types of the variable. *)
    "type_check-m-7" >:: (fun _ ->
        assert_equal_tes
          (TargetEnvs.of_list @@ [
              (ty_np, [
                  (senv false 0 "pr", empty_ctx);
                  (senv false 0 "np", empty_ctx)
                ])
            ]) @@
        typing#type_check (hg#nt_body 5) (Some ty_np) empty_ctx false false
      );

    (* Typing identity should work for both types of the variable. *)
    "type_check-m-8" >:: (fun _ ->
        let var_bix = [(0, (0, 0))] in
        let bix_hty = [
          (0, [
              [ity_of_string "pr"];
              [ity_of_string "np"]
            ])
        ] in
        let bix_hty1 = [
          (0, [
              [ity_of_string "pr"]
            ])
        ] in
        let bix_hty2 = [
          (0, [
              [ity_of_string "np"]
            ])
        ] in
        let ctx = lctx var_bix bix_hty None None in
        assert_equal_tes
          (TargetEnvs.of_list @@ [
              (ty_np, [
                  (senv false 0 "pr", lctx var_bix bix_hty1 None None);
                  (senv false 0 "np", lctx var_bix bix_hty2 None None)
                ])
            ]) @@
        typing#type_check (hg#nt_body 5) (Some ty_np) ctx false false
      );

    (* Forcing usable nonterminal typing. *)
    "type_check-m-9" >:: (fun _ ->
        let ctx = lctx [] [] None @@ Some ([1; 2], TySet.of_string "np -> np") in
        let used_nts = NTTyMap.of_list [
            ((5, ty_of_string "np -> np"), true);
            ((4, ty_of_string "(np -> np) -> (np -> np) -> np -> np"), false)
          ] in
        assert_equal_tes
          (TargetEnvs.of_list @@ [
              (ty_np, [
                  (mk_env used_nts empty_loc_types false IntMap.empty, lctx [] [] None None);
                ])
            ]) @@
        typing#type_check (hg#nt_body 3) (Some ty_np) ctx false false
      );

    (* Forcing unusable nonterminal typing. *)
    "type_check-m-10" >:: (fun _ ->
        let ctx = lctx [] [] None @@ Some ([1; 2], TySet.of_string "pr -> np") in
        assert_equal_tes
          TargetEnvs.empty @@
        typing#type_check (hg#nt_body 3) (Some ty_np) ctx false false
      );
  ]



(** Testing grammars from examples directory under specific conditions. *)
let typing_examples_border_cases () =
  [
    (* regression test *)
    "type_check-ex-1" >:: (fun _ ->
        let hg, typing = mk_examples_typing "examples/dependencies_inf.inf" in
        let id_into_A = hg#locate_hterms_id 3 [0; 1; 0] in
        ignore @@ typing#add_hterms_hty id_into_A @@
        [|tys_top; TySet.of_string "np -> pr"; TySet.of_string "np"|];
        ignore @@ typing#add_hterms_hty id_into_A @@
        [|tys_top; TySet.of_string "np -> pr"; tys_top|];
        ignore @@ typing#add_hterms_hty id_into_A @@
        [|tys_top; tys_top; TySet.of_string "np"|];
        ignore @@ typing#add_hterms_hty id_into_A @@
        [|tys_top; tys_top; tys_top|];
        ignore @@ typing#add_nt_ty 4 @@ ty_of_string "T -> (np -> pr) -> np -> np";
        let ctx = typing#binding2ctx (hg#nt_body 3) None None None [(0, 2, id_into_A)] in
        let ctx_expected =
          lctx [(0, (0, 0)); (1, (0, 1)); (2, (0, 2))]
            [(0, [[ity_top; ity_of_string "np -> pr"; ity_of_string "np"]])] None None
        in
        let used_nts =
          NTTyMap.singleton (4, ty_of_string "T -> (np -> pr) -> np -> np") false
        in
        assert_equal_tes
          (TargetEnvs.of_list @@ [
              (ty_np, [
                  (mk_env used_nts empty_loc_types false @@
                   IntMap.of_list [(1, ity_of_string "np -> pr"); (2, ity_of_string "np")],
                   ctx_expected)
                ])
            ]) @@
        typing#type_check (hg#nt_body 3) None ctx false false
      );

    (* sub-case of 1 with the bug *)
    "type_check-ex-2" >:: (fun _ ->
        let hg, typing = mk_examples_typing "examples/dependencies_inf.inf" in
        let id_into_A = hg#locate_hterms_id 3 [0; 1; 0] in
        ignore @@ typing#add_hterms_hty id_into_A @@
        [|tys_top; TySet.of_string "np -> pr"; TySet.of_string "np"|];
        ignore @@ typing#add_nt_ty 4 @@ ty_of_string "T -> (np -> pr) -> np -> np";
        let ctx = typing#binding2ctx (hg#nt_body 3) None None None [(0, 2, id_into_A)] in
        let id_A_xyz = hg#locate_hterms_id 3 [0; 0; 0] in
        let used_nts =
          NTTyMap.singleton (4, ty_of_string "T -> (np -> pr) -> np -> np") false
        in
        assert_equal_tes
          (TargetEnvs.of_list @@ [
              (ty_np, [
                  (mk_env used_nts empty_loc_types false @@
                   IntMap.of_list [(1, ity_of_string "np -> pr"); (2, ity_of_string "np")],
                   ctx)
                ])
            ]) @@
        typing#type_check (HNT 4, [id_A_xyz]) (Some ty_np) ctx false true
      );
  ]
  

let typing_test () : test =
  init_flags ();
  "typing" >:::
  typing_e_test () @
  typing_ax_test () @
  typing_xyyz_test () @
  typing_dup_test () @
  typing_double_test () @
  typing_misc_test () @
  typing_examples_border_cases ()



let cfa_test () : test =
  init_flags ();
  let hg_xyyz = mk_hgrammar @@ grammar_xyyz () in
  let cfa_xyyz = mk_cfa hg_xyyz in
  let hg_dup = mk_hgrammar @@ grammar_dup () in
  let cfa_dup = mk_cfa hg_dup in
  let hg_double = mk_hgrammar @@ grammar_double () in
  let cfa_double = mk_cfa hg_double in
  "cfa" >::: [
    (* empty binding with no variables *)
    "nt_binding-1" >:: (fun _ ->
        assert_equal
          [[]]
          (cfa_xyyz#lookup_nt_bindings 0)
      );

    (* single binding, directly *)
    "nt_binding-2" >:: (fun _ ->
        assert_equal
          [
            [(0, 2, List.hd @@ snd @@ hg_xyyz#nt_body 0)]
          ]
          (cfa_xyyz#lookup_nt_bindings 1)
      );

    (* two bindings, both indirectly due to partial application *)
    "nt_binding-3" >:: (fun _ ->
        assert_equal
          [
            "[nt2v2]";
            "[nt3v1]"
          ]
          (List.sort compare @@ List.map (fun binding ->
               match binding with
               | [(_, _, id)] -> hg_xyyz#string_of_hterms id
               | _ -> failwith "Expected singleton binding."
             ) @@ cfa_xyyz#lookup_nt_bindings 4)
      );

    (* no bindings when unreachable *)
    "nt_binding-4" >:: (fun _ ->
        assert_equal
          []
          (cfa_xyyz#lookup_nt_bindings 5)
      );

    (* binding with args from different nonterminals *)
    "nt_binding-5" >:: (fun _ ->
        assert_equal
          [
            [
              (* a in N5 *)
              (0, 0, hg_dup#locate_hterms_id 5 [0; 0; 0]);
              (* a <var> in N6 *)
              (1, 2, hg_dup#locate_hterms_id 6 [0])
            ]
          ]
          (cfa_dup#lookup_nt_bindings 4)
      );

    (* Two bindings for N1 in grammar_double. *)
    "nt_binding-6" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq
          [
            [
              (0, 1, hg_double#locate_hterms_id 0 [0])
            ];
            [
              (0, 1, hg_double#locate_hterms_id 1 [0; 1; 0])
            ]
          ]
          (cfa_double#lookup_nt_bindings 1)
      );
    
    (* One binding for N2 in grammar_double, a binding with two identical hterms. *)
    "nt_binding-7" >:: (fun _ ->
        assert_equal ~cmp:list_sort_eq
          [
            [
              (* N2 [y] [y] after substitution in N1 *)
              (0, 0, hg_double#locate_hterms_id 1 [0; 0; 0]);
              (1, 1, hg_double#locate_hterms_id 1 [0; 0; 0])
            ]
          ]
          (cfa_double#lookup_nt_bindings 2)
      );
    
    (* checking that cfa detected that in N0 nonterminal N1 was applied to N4 *)
    "var_binding-1" >:: (fun _ ->
        assert_equal
          [
            (HNT 4, [])
          ]
          (cfa_xyyz#lookup_binding_var (1, 1))
      );
  ]



let proof_test () : test =
  init_flags ();
  "proof" >::: [
    "proof-1" >:: (fun _ ->
        match Main.parse_and_report_finiteness @@ Some "examples/multiple_usages_inf.inf" with
        | Infinite cycle_proof_str ->
          assert_regexp_count 1 (Str.regexp_string "I (x2)") cycle_proof_str;
          assert_regexp_count 3 (Str.regexp_string "(+)") cycle_proof_str;
          assert_regexp_count 1 (Str.regexp_string "(x2)") cycle_proof_str;
          assert_regexp_count 2 (Str.regexp_string "x#1") cycle_proof_str;
          assert_regexp_count 2 (Str.regexp_string "x#2") cycle_proof_str;
          assert_regexp_count 0 (Str.regexp_string "C#1") cycle_proof_str;
          assert_regexp_count 0 (Str.regexp_string "S#1") cycle_proof_str;
          assert_regexp_count 0 (Str.regexp_string "I#1") cycle_proof_str;
          assert_regexp_count 1 (Str.regexp "C :.*\n.*C :") cycle_proof_str;
          assert_regexp_count 1 (Str.regexp "A :.*/\\\\") cycle_proof_str
        | Finite | Unknown ->
          failwith "Expected infinite saturation result."
      );
  ]



let examples_test () : test =
  init_flags ();
  let filenames_in_dir = List.filter (fun f -> String.length f > 8)
      (Array.to_list (Sys.readdir "examples")) in
  let inf_filenames = List.filter (fun f ->
      String.sub f (String.length f - 8) 8 = "_inf.inf") filenames_in_dir in
  let fin_filenames = List.filter (fun f ->
      String.sub f (String.length f - 8) 8 = "_fin.inf") filenames_in_dir in
  let path filename = Some (String.concat "" ["examples/"; filename]) in
  let run filename =
    if String.length filename > 15 &&
       String.sub filename (String.length filename - 15) 7 = "_unsafe" then
      begin
        let unsafe_before = !Flags.force_unsafe in
        Flags.force_unsafe := true;
        let res = Main.parse_and_report_finiteness (path filename) in
        Flags.force_unsafe := unsafe_before;
        res
      end
    else
      Main.parse_and_report_finiteness (path filename)
  in
  let flag_states = [true; false] in
  let all_flag_states = product [flag_states; flag_states; flag_states] in
  let tests : test list =
    all_flag_states |>
    List.map (function
        | [no_headvar_opt; no_force_hterms_hty_opt; no_force_nt_ty_opt] as flags ->
          Flags.no_headvar_opt := no_headvar_opt;
          Flags.no_force_hterms_hty_opt := no_force_hterms_hty_opt;
          Flags.no_force_nt_ty_opt := no_force_nt_ty_opt;
          let name = "flags-" ^ concat_map "-" string_of_bool flags in
          name >::: [
            "Infinite examples" >::: List.map (fun filename ->
                filename >:: (fun _ ->
                    assert_equal ~printer:id "infinite" @@
                    Saturation.string_of_infsat_result @@ run filename))
              inf_filenames;
            "Finite examples" >::: List.map (fun filename ->
                filename >:: (fun _ ->
                    assert_equal ~printer:Saturation.string_of_infsat_result Finite @@
                    run filename))
              fin_filenames
          ]
        | _ -> failwith "Unreachable"
      )
  in
  "Examples" >::: tests



let tests () = [
  utilities_test ();
  ctx_test ();
  dfg_test ();
  conversion_test ();
  cfa_test ();
  te_test ();
  type_test ();
  typing_test ();
  proof_test ();
  examples_test ()
]
