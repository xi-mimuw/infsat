open Profiling
open Utilities

(** Parses a file to HORS prerules and automata definition. *)
let parse_file filename =
  let in_strm = 
    try
      open_in filename 
    with
	Sys_error _ -> (print_string ("Cannot open file: "^filename^"\n");exit(-1)) in
  print_string ("Analyzing "^filename^".\n");
  flush stdout;
  let lexbuf = Lexing.from_channel in_strm in
  let result =
    try
      InfSatParser.main InfSatLexer.token lexbuf
    with 
	Failure _ -> exit(-1) (*** exception raised by the lexical analyer ***)
      | Parsing.Parse_error -> (print_string "Parse error\n";exit(-1)) in
  let _ = 
    try
      close_in in_strm
    with
	Sys_error _ -> (print_string ("Cannot close file: "^filename^"\n");exit(-1)) 
  in
    result

(** Parses stdin to HORS prerules and automata transitions. *)
let parse_stdin() =
  let _ = print_string ("reading standard input ...\n") in
  let in_strm = stdin in
  let lexbuf = Lexing.from_channel in_strm in
  let result =
    try
      InfSatParser.main InfSatLexer.token lexbuf
    with 
    | Failure _ -> exit(-1) (* exception raised by the lexical analyer *)
    | Parsing.Parse_error -> (print_string "Parse error\n";exit(-1)) 
  in
    result

(** Main part of InfSat. Takes parsed input, computes if the language contains
    arbitrarily many counted letters. Prints the result. *)
let report_finiteness input : bool =
  let grammar = profile "conversion" (fun () -> Conversion.prerules2gram input) in
  profile "eta-expansion" (fun () -> Stype.eta_expand grammar);
  let hgrammar = profile "head conversion" (fun () -> new HGrammar.hgrammar grammar) in
  let cfa = profile "0CFA" (fun () ->
      let cfa = new Cfa.cfa grammar hgrammar (* TODO Cfa.init_expansion () *) in
      cfa#expand;
      cfa#mk_binding_depgraph;
      cfa)
  in
  profile "saturation" (fun () ->
      true
        (*
      let saturation = new Saturation.saturation cfa hgrammar in
      saturation#saturate
*)
    )

let string_of_input (prerules, tr) =
  (Syntax.string_of_prerules prerules)^"\n"^(Syntax.string_of_preterminals tr)

let report_usage () =
  print_string "Usage: \n";
  print_string "infsat <option>* <filename> \n\n";
  print_string " -d\n";
  print_string "  debug mode\n"

let rec read_options index =
  match Sys.argv.(index) with
  | "-d" -> (Flags.debugging := true; read_options (index+1))
  | "-noce" -> (Flags.ce := false; read_options (index+1))
  | "-subt" -> (Flags.subty := true; read_options (index+1))
  | "-o" -> (Flags.outputfile := Sys.argv.(index+1); read_options (index+2))
  | "-r" -> (Flags.redstep := int_of_string(Sys.argv.(index+1));
             Flags.flow := false;
             read_options(index+2))
  | "-n" -> (Flags.normalize := true;
             Flags.normalization_depth := int_of_string(Sys.argv.(index+1));
             read_options(index+2))
  | "-lazy" -> (Flags.eager := false;
			      read_options(index+1))
  | "-merge" -> (Flags.merge_vte := true;
			      read_options(index+1))
  | "-nn" -> (Flags.normalize := false;
			      read_options(index+1))
  | "-tyterm2" -> (Flags.ty_of_term := true;read_options(index+1))
  | "-c" -> (Flags.compute_alltypes := true;read_options (index+1))
  | "-noinc" -> (Flags.incremental := false;read_options (index+1))
  | "-nooverwrite" -> (Flags.overwrite := false;read_options (index+1))
  | "-subty" -> (Flags.subtype_hash := true;read_options (index+1))
  | "-nosubty" -> (Flags.nosubtype := true;read_options (index+1))
  | "-ne" -> (Flags.emptiness_check := false; read_options (index+1))
  | "-bdd" -> (Flags.bdd_mode := 1; read_options (index+1))
  | "-bdd2" -> (Flags.bdd_mode := 2; read_options (index+1))
  | "-prof" -> (Flags.profile := true; read_options (index+1))
  | "-flowcts" -> (Flags.add_flow_cts := true; read_options (index+1))
  | "-notenv" -> (Flags.report_type_env := false; read_options (index+1))
  | "-v" -> (Flags.verbose := true; read_options (index+1))
  | "-cert" -> (Flags.certificate := true; read_options (index+1))
  | _ -> index

let parse_and_report_finiteness (filename : string option) : bool =
  let input = profile "parsing" (fun () ->
      try
        match filename with
        | Some(f) -> parse_file f
        | None -> parse_stdin()
      with
        InfSatLexer.LexError s -> failwith ("Lexer error: "^s)
    )
  in
  if !Flags.debugging then
    print_string ("Input:\n"^(string_of_input input));
  report_finiteness input
  
let main() : unit =
  let _ = print_string "InfSat2 0.1: Saturation-based finiteness checker for higher-order recursion schemes\n" in
  flush stdout;
  let filename = 
    try
      Some (Sys.argv.(read_options 1))
    with
    | Invalid_argument _ -> None
    | _ -> 
      print_string "Invalid options.\n\n";
      report_usage();
      exit (-1)
  in
  let start_t = Sys.time() in
  ignore (parse_and_report_finiteness filename);
  let end_t = Sys.time() in
  report_timings start_t end_t
