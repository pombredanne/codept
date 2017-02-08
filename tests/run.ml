module Pth = Paths.Pkg

let local = Pth.local

let (%) f g x = f (g x)

let classify filename =  match Filename.extension filename with
  | ".ml" -> { Read.format= Src; kind  = M2l.Structure }
  | ".mli" -> { Read.format = Src; kind = M2l.Signature }
  | _ -> raise (Invalid_argument "unknown extension")


let policy = Standard_policies.quiet

let organize policy files =
  files
  |> Unit.unimap (List.map @@ fun (info,f) -> Unit.read_file policy info f)
  |> Unit.Groups.Unit.(split % group)


module Envt = Envts.Tr

let start_env includes fileset =
  let base = Envts.Base.start @@ Module.Sig.flatten Stdlib.signature in
  let layered = Envts.Layered.create includes fileset base in
  let traced = Envts.Trl.extend layered in
  Envt.start traced fileset

module Param = struct
  let policy = policy
  let transparent_aliases = true
  let transparent_extension_nodes = true
end

module S = Solver.Make(Envt)(Param)

let analyze pkgs files =
  let units = organize policy files in
  let fileset = units.Unit.mli
                |> List.map (fun (u:Unit.s) -> u.name)
                |> Name.Set.of_list in
  let module Envt = Envts.Tr in
  let core = start_env pkgs fileset in
  S.resolve_split_dependencies core units


let ok_only = function
  | Ok l -> l
  | Error (`Ml (_, state) | `Mli state)  ->
      Fault.Log.critical "%a" Solver.Failure.pp_cycle state.S.pending

let normalize set =
  set
  |> Deps.Forget.to_list
  |> List.map Pth.module_name
  |> List.sort compare


let simple_dep_test name list set =
  let r = normalize set = List.sort compare list in
  if not r then
    Pp.p "Failure %a(%s): expected:[%a], got:@[[%a]@]\n"
      Pth.pp name (Sys.getcwd ())
      Pp.(list estring) (List.sort compare list)
      Pp.(list estring) (normalize set);
  r


let (%) f g x = f (g x)

let normalize_2 set =
  let l = Deps.Forget.to_list set in
  let is_inner =
    function { Pth.source = Local; _ } -> true | _ -> false in
  let is_lib =
    function { Pth.source = (Pkg _ | Special _ ) ; _ } -> true
           | _ -> false in
  let inner, rest = List.partition is_inner l in
  let lib, unkn = List.partition is_lib rest in
  let norm = List.sort compare % List.map Pth.module_name in
  norm inner, norm lib, norm unkn


let precise_deps_test name (inner,lib,unkw) set =
  let sort = List.sort compare in
  let inner, lib, unkw = sort inner, sort lib, sort unkw in
  let inner', lib', unkw' = normalize_2 set in
  let test subtitle x y =
    let r = x = y  in
    if not r then
      Pp.p "Failure %a %s: expected:[%a], got:@[[%a]@]\n"
      Pth.pp name subtitle
      Pp.(list estring) x
      Pp.(list estring) y;
    r in
  test "local" inner inner'
  && test "lib" lib lib'
  && test "unknwon" unkw unkw'

let add_info {Unit.ml; mli} (f, info) =
  let k = classify f in
  match k.kind with
  | M2l.Structure -> { Unit.ml = (k,f,info) :: ml; mli }
  | M2l.Signature -> { Unit.mli = (k,f,info) :: mli; ml }

let add_file {Unit.ml; mli} file =
 let k = classify file in
  match k.kind with
  | M2l.Structure -> { Unit.ml = (k,file) :: ml; mli }
  | M2l.Signature -> { Unit.mli = (k,file) :: mli; ml }

let gen_deps_test libs inner_test l =
  let {Unit.ml;mli} = List.fold_left add_info {Unit.ml=[]; mli=[]} l in
  let module M = Paths.S.Map in
  let build exp = List.fold_left (fun m (_,x,l) ->
      M.add (Paths.S.parse_filename x) l m)
      M.empty exp in
  let exp = M.union' (build ml) (build mli) in
  let sel (k,f,_) = k, f in
  let files = Unit.unimap (List.map sel) {ml;mli} in
  let {Unit.ml; mli} = ok_only @@ analyze libs files in
  let (=?) expect files = List.for_all (fun u ->
      let path = u.Unit.path.Pth.file in
      let expected =
          Paths.S.Map.find path expect
      in
      inner_test u.path expected u.dependencies
    ) files in
  exp =? ml && exp =? mli

let deps_test l =
  gen_deps_test [] simple_dep_test l

let ocamlfind name =
  let cmd = "ocamlfind query " ^ name in
  let cin = Unix.open_process_in cmd in
  try
    [input_line cin]
  with
    End_of_file -> []

let cycle_test expected l =
    let files = List.fold_left add_file {Unit.ml=[]; mli=[]} l in
    match analyze [] files with
    | Ok _ -> false
    | Error( `Mli state | `Ml (_, state) )->
      let open Solver.Failure in
      let units = state.pending in
      let _, cmap = analyze units in
      let errs = Map.bindings cmap in
      let name unit = Solver.(unit.input.name) in
      let cycles = errs
                  |> List.filter (function (Cycle _, _) -> true | _ -> false)
                  |> List.map snd
                  |> List.map (List.map name % Solver.Failure.Set.elements) in
      let expected = List.map (List.sort compare) expected in
      let cycles = List.map (List.sort compare) cycles in
      let r = cycles = expected in
      if not r then
        ( Pp.fp Pp.std "Failure: expected %a, got %a\n"
            Pp.(list @@ list string) expected
            Pp.(list @@ list string) cycles;
          r )
      else
        r



let result =
  Sys.chdir "tests/cases";
  List.for_all deps_test [
    ["abstract_module_type.ml", []];
    ["alias_map.ml", ["Aliased__B"; "Aliased__C"] ];
    ["apply.ml", ["F"; "X"]];
    ["basic.ml", ["Ext"; "Ext2"]];
    ["bindings.ml", []];
    ["bug.ml", ["Sys"] ];
    ["case.ml", ["A"; "B";"C";"D";"F"]];
    ["even_more_functor.ml", ["E"; "A"]];
    ["first-class-modules.ml", ["Mark";"B"] ];
    ["first_class_more.ml", [] ];
    ["foreign_arg_sig.ml", ["Ext";"Ext2"] ];
    ["functor.ml", [] ];
    ["functor_with_include.ml", [] ];
    [ "hidden.ml", ["Ext"] ];
    ["imperfect_modules.ml", ["Ext"] ];
    ["include.ml", ["List"] ];
    ["include_functor.ml", ["A"] ];
    ["letin.ml", ["List"] ];
    ["let_open.ml", [] ];
    ["module_rec.ml", ["Set"] ];
    ["module_types.ml", ["B"] ];
    ["more_functor.ml", ["Ext";"Ext2"] ];
    ["nested_modules.ml", [] ];
    ["no_deps.ml", [] ];
    ["not_self_cycle.ml", ["E"] ];
    ["nothing.ml", [] ];
    ["unknown_arg.ml", ["Ext"] ];
    ["opens.ml", ["A";"B"] ];
    ["pattern_open.ml", ["A'";"E1"; "E2"; "E3";"E4"] ];
    ["phantom_maze.ml", ["External"; "B"; "C";"D"; "E"; "X"; "Y" ] ];
    ["phantom_maze_2.ml", ["E"; "D"]];
    ["phantom_maze_3.ml", ["B"; "X"] ];
    ["phantom_maze_4.ml", ["Extern"] ];
    ["recmods.ml", ["Ext"]];
    ["record.ml", ["Ext";"E2";"E3"]];
    ["simple.ml", ["G";"E"; "I"; "A"; "W"; "B"; "C"; "Y"; "Ext"]];
    ["solvable.ml", ["Extern"]];
    ["tuple.ml", ["A"; "B"; "C"]];
    ["unknown_arg.ml", ["Ext"] ];
    ["with.ml", ["Ext"] ]


  ]
  (* Note the inferred dependencies is wrong, but there is not much
     (or far too much ) to do here *)
  && deps_test  [ "riddle.ml", ["M5"] ]
  &&
  List.for_all deps_test [
    ["broken.ml", ["Ext"; "Ext2"; "Ext3"; "Ext4"; "Ext5" ] ];
    ["broken2.ml", ["A"; "Ext"; "Ext2" ]];
      ["broken3.ml", []];
  ]
  &&( Sys.chdir "../mixed";
      deps_test ["a.ml", ["D"];
                 "a.mli", ["D";"B"];
                 "b.ml", ["C"];
                 "c.mli", ["D"];
                 "d.mli", []
                ]
    )
  && ( Sys.chdir "../aliases";
       deps_test [ "amap.ml", ["Long__B"];
                   "user.ml", ["Amap"; "Long__A"];
                   "long__A.ml", [];
                   "long__B.ml", []
                 ]
     )
  && ( Sys.chdir "../aliases2";
       deps_test [ "a.ml", ["B"; "D" ];
                   "b.ml", [];
                   "c.ml", [];
                   "d.ml", [];
                   "e.ml", []
                 ]
     )
  && (Sys.chdir "../aliases_and_map";
      deps_test ["n__A.ml", ["M"];
                 "n__B.ml", ["M"];
                 "n__C.ml", ["M"; "N__A"];
                 "n__D.ml", ["M"; "N__B"];
                 "m.ml", [];
                 "n__A.mli", ["M"];
                 "n__B.mli", ["M"];
                 "n__C.mli", ["M"];
                 "n__D.mli", ["M"];
                 "m.mli", [];
                ]
     )
  &&
  ( Sys.chdir "../broken_network";
    deps_test [
      "a.ml", ["Broken"; "B"; "C"];
      "broken.ml", ["B"];
      "c.ml", ["Extern"] ]
  )
  &&
  ( Sys.chdir "../network";
  deps_test ["a.ml", ["B"; "Extern"]; "b.ml", []; "c.ml", ["A"] ]
  )
  &&
  ( Sys.chdir "../collision";
    deps_test ["a.ml", ["B"; "Ext"];
               "b.ml", [];
               "c.ml", ["B"];
               "d.ml", ["B"] ]
  )
  &&
  ( Sys.chdir "../pair";
  deps_test ["a.ml", ["B"];  "b.ml", ["Extern"] ]
  )
  &&
  ( Sys.chdir "../namespaced";
    deps_test [ "NAME__a.ml", ["Main"; "NAME__b"];
                "NAME__b.ml", ["Main"; "NAME__c"];
                "NAME__c.ml", ["Main"];
                "main.ml", []
              ]
  )
  &&
  ( Sys.chdir "../module_types";
  deps_test ["a.mli", ["E"];  "b.ml", ["A"] ]
  )
  && (
    let n = 100 in
    let dep = [ Printf.sprintf "M%d" n ] in
    Sys.chdir "../star";
    ignore @@ Sys.command (Printf.sprintf "ocaml generator.ml %d" 100);
    let rec deps k =
      if k >= n then
        [ Printf.sprintf "m%03d.mli" k, [] ]
      else
        (Printf.sprintf "m%03d.mli" k, dep) :: (deps @@ k+1) in
    deps_test @@ deps 1
  )
    &&
  ( Sys.chdir "../stops";
    deps_test ["a.ml", ["B"; "C"; "D"; "E"; "F"]
              ; "b.ml", ["Z"]
              ; "c.ml", ["Y"]
              ; "d.ml", ["X"]
              ; "e.ml", ["W"]
              ; "f.ml", ["V"]
              ; "v.ml", ["E"]
              ; "w.ml", ["D"]
              ; "x.ml", ["C"]
              ; "y.ml", ["B"]
              ; "z.ml", []
              ]
)
    && (
      Sys.chdir "../cases";
      cycle_test [["Self_cycle"]] ["self_cycle.ml"]
    )
    &&
    (
      Sys.chdir "../ω-cycle";
      cycle_test [["C1";"C2";"C3";"C4";"C5"]] [ "a.ml"
                    ; "b.ml"
                    ; "c1.ml"
                    ; "c2.ml"
                    ; "c3.ml"
                    ; "c4.ml"
                    ; "c5.ml"
                    ; "k.ml"
                    ; "l.ml"
                    ; "w.ml"
                                              ]
    )
    && (
      Sys.chdir "../2+2-cycles";
      cycle_test [["A";"B"]; ["C";"D"]] [ "a.ml" ; "b.ml"; "c.ml"; "d.ml"]
    )
    &&
    ( Sys.chdir "../../lib";
      gen_deps_test (ocamlfind "compiler-libs") precise_deps_test
        [
          "ast_converter.mli", ( ["M2l"], ["Parsetree"], [] );
          "ast_converter.ml", ( ["Loc"; "M2l"; "Name"; "Option"; "Module";
                                 "Paths"],
                                ["List";"Longident"; "Location"; "Lexing";
                                 "Parsetree"], [] );
          "approx_parser.mli", (["M2l"], [],[]);
          "approx_parser.ml", (["Deps"; "Loc"; "Read";"M2l";"Name"],
                               ["Lexer"; "Parser"; "Lexing";"List"],[]);
          "cmi.mli", (["M2l"], [], []);

          "cmi.ml", (["Loc"; "M2l";"Module"; "Option"; "Paths"],
                     ["Cmi_format"; "List"; "Path";"Types"], []);
          "deps.ml", (["Option"; "Paths"; "Pp"; "Sexp"],["List"],[]);
          "summary.mli", (["Module"], ["Format"], []);
          "summary.ml", (["Module"; "Name"; "Pp"; "Mresult"], ["List"], []);
          "envts.mli", (["Deps"; "Module";"Name"; "Interpreter"; "Paths"], [], []);
          "envts.ml", (
            ["Cmi"; "Deps"; "Summary"; "Interpreter"; "M2l"; "Fault";
             "Module"; "Name"; "Paths";"Standard_faults";"Standard_policies"],
            ["Array"; "Filename"; "List";"Sys"],
            []);
          "interpreter.mli", (["Deps"; "Fault"; "Module";"Paths";"M2l";"Summary"],
                              [],[]);
          "interpreter.ml", (
            ["Summary"; "Loc"; "M2l"; "Module"; "Name"; "Option"; "Paths";
             "Mresult"; "Fault"; "Standard_faults"; "Deps"]
          ,["List"],[]);
          "m2l.mli", (["Deps";"Loc"; "Module";"Name";"Summary";"Paths";"Sexp" ],
                      ["Format"],[]);
          "m2l.ml", (["Loc"; "Deps"; "Module"; "Mresult"; "Name";
                      "Option";"Summary";"Paths"; "Pp"; "Sexp" ],
                     ["List"],[]);
          "fault.ml", (["Loc"; "Option"; "Name";"Paths"; "Pp"],
                          ["Array"; "Format"],[]);
          "fault.mli", (["Loc"; "Paths"; "Name"],
                          ["Format"],[]);

          "module.mli", ( ["Loc";"Paths";"Name"; "Sexp"], ["Format"], [] );
          "module.ml", ( ["Loc";"Paths";"Name"; "Pp"; "Sexp" ], ["List"], [] );
          "name.mli", ( [], ["Format";"Set";"Map"], [] );
          "name.ml", ( ["Pp"], ["Set";"Map"], [] );
          "loc.mli", ( ["Sexp"], ["Format"], []);
          "loc.ml", ( ["Pp";"Sexp"], ["List"], []);
          "option.mli", ([],[],[]);
          "option.ml", ([],["List"],[]);
          "paths.mli", (["Name"; "Sexp"], ["Map";"Set";"Format"],[]);
          "paths.ml", (["Name"; "Pp"; "Sexp" ],
                       ["Filename";"List";"Map";"Set";"Format"; "String"],[]);
          "pp.mli", ([], ["Format"],[]);
          "pp.ml", ([], ["Format"],[]);
          "read.mli", (["M2l"; "Name"],["Syntaxerr"],[]);
          "read.ml", (["Ast_converter"; "Cmi"; "M2l"],
                      ["Filename"; "Format"; "Lexing"; "Location"; "Parse";
                       "Parsing"; "Pparse"; "String"; "Syntaxerr"],
                      ["Sexp_parse"; "Sexp_lex"]);
          "mresult.mli", ([],[],[]);
          "mresult.ml", ([],["List"],[]);
          "sexp.ml", (["Name"; "Option"; "Pp"],
                      [ "Obj"; "Format";"List";"Map"; "Hashtbl"; "String"], [] );
          "sexp.mli", (["Name"],
                      [ "Format"], [] );
          "solver.mli", (["Deps"; "Loc"; "Unit";"M2l";"Name";"Interpreter"; "Paths"],
                         ["Format";"Map";"Set"],[]);
          "solver.ml", (
            ["Approx_parser"; "Deps"; "Summary"; "Interpreter"; "Loc";
             "M2l"; "Module"; "Mresult"; "Name"; "Option"; "Pp"; "Paths"; "Unit";
             "Fault"; "Standard_faults"],
            ["List"; "Map"; "Set"],[]);
          "standard_faults.ml", (["Fault"; "Module"; "Paths"; "Pp"; "Loc" ],
                                 ["Format"; "Location"; "Syntaxerr"],[]);
          "standard_faults.mli", (["Fault"; "Name"; "Module"; "Paths" ],
                                  ["Syntaxerr"],[]);
          "standard_policies.ml", (["Fault"; "Standard_faults"],[],[]);
          "standard_policies.mli", (["Fault"],[],[]);
          "unit.mli", (["Deps";"Paths"; "M2l"; "Module"; "Name"; "Fault"; "Read"],
                       ["Format";"Set"],[]);
          "unit.ml", (
            ["Approx_parser"; "Deps"; "M2l"; "Module"; "Fault";
             "Option"; "Paths"; "Pp"; "Read"; "Standard_faults"],
            [ "List"; "Set"],
            []);
        ]
    )
let () =
  if result then
    Format.printf "Success.\n"
  else
    Format.printf "Failure.\n"
