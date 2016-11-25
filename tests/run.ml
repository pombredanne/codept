module Pth = Paths.Pkg

let local file = Pth.local @@ Paths.S.parse_filename file

let organize files =
  let add_name m n  =  Name.Map.add (Unit.extract_name n) (local n) m in
  let m = List.fold_left add_name
      Name.Map.empty (files.Unit.ml @ files.mli) in
  let units = Unit.( split @@ group files ) in
  units, m


let start_env filemap =
  let layered = Envts.Layered.create [] @@ Stdlib.signature in
  let traced = Envts.Trl.extend layered in
  Envts.Tr.start traced filemap

module Param = struct
  let all = false
  let native = false
  let bytecode = false
  let abs_path = false
  let sort = false
  let slash = Filename.dir_sep
  let transparent_aliases = true
  let transparent_extension_nodes = true
  let includes = Name.Map.empty
  let implicits = true
  let no_stdlib = false
end

module S = Solver.Make(Param)

let analyze files =
  let units, filemap = organize files in
  let module Envt = Envts.Tr in
  let core = start_env filemap in
    S.resolve_split_dependencies core units

let normalize set =
  set
  |> Pth.Set.elements
  |> List.map Pth.module_name
  |> List.sort compare


let (%=%) list set =
  normalize set = List.sort compare list

let deps_test {Unit.ml; mli} =
  let module M = Paths.S.Map in
  let build exp = List.fold_left (fun m (x,l) ->
      M.add (Paths.S.parse_filename x) l m)
      M.empty exp in
  let exp = M.union' (build ml) (build mli) in
  let files = { Unit.ml = List.map fst ml; mli =  List.map fst mli} in
  let {Unit.ml; mli} = analyze files in
  let (=?) expect files = List.for_all (fun u ->
      let path = u.Unit.path.Pth.file in
      let expected =
          Paths.S.Map.find path expect
      in
      let r = expected %=% u.Unit.dependencies in
      if not r then
        Pp.p "Failure %a: expected:[%a], got:@[[%a]@]\n"
          Pth.pp u.Unit.path
          Pp.(list estring) (List.sort compare expected)
          Pp.(list estring) (normalize u.Unit.dependencies);
      r
    ) files in
  exp =? ml && exp =? mli

let ml_only ml = { Unit.mli = []; ml }
let mli_only mli = { Unit.ml = []; mli }

let result =
  Sys.chdir "tests";
  List.for_all deps_test [
    ml_only ["abstract_module_type.ml", []];
    ml_only ["alias_map.ml", ["Aliased__B"; "Aliased__C"] ];
    ml_only ["apply.ml", ["F"; "X"]];
    ml_only ["basic.ml", ["Ext"; "Ext2"]];
    ml_only ["bindings.ml", []];
    ml_only ["bug.ml", ["Sys"] ];
    ml_only ["case.ml", ["A"; "B";"C";"D";"F"]];
    ml_only ["even_more_functor.ml", ["E"; "A"]];
    ml_only ["first-class-modules.ml", ["Mark";"B"] ];
    ml_only ["first_class_more.ml", [] ];
    ml_only ["functor.ml", [] ];
    ml_only ["functor_with_include.ml", [] ];
    ml_only ["include.ml", ["List"] ];
    ml_only ["include_functor.ml", ["A"] ];
    ml_only ["letin.ml", ["List"] ];
    ml_only ["module_rec.ml", ["Set"] ];
    ml_only ["more_functor.ml", ["Ext";"Ext2"] ];
    ml_only ["nested_modules.ml", [] ];
    ml_only ["no_deps.ml", [] ];
    ml_only ["opens.ml", ["A";"B"] ];
    ml_only ["pattern_open.ml", ["E1"; "E2"; "E3";"E4"] ];
    ml_only ["recmods.ml", ["Ext"]];
    ml_only ["record.ml", ["Ext";"E2";"E3"]];
    ml_only ["simple.ml", ["G";"E"; "I"; "A"; "W"; "B"; "C"; "Y"; "Ext"]];
    ml_only ["solvable.ml", ["Extern"]];
    ml_only ["tuple.ml", ["A"; "B"; "C"]];
    ml_only ["with.ml", ["Ext"] ]


  ]
  &&
  ( Sys.chdir "network";
  deps_test (ml_only ["a.ml", ["B"; "Extern"]; "b.ml", []; "c.ml", ["A"] ] )
  )
  &&
  ( Sys.chdir "../collision";
    deps_test (ml_only ["a.ml", ["B"; "Ext"];
                        "b.ml", [];
                        "c.ml", ["B"];
                        "d.ml", ["B"] ] )
  )
  &&
  ( Sys.chdir "../pair";
  deps_test (ml_only ["a.ml", ["B"];  "b.ml", ["Extern"] ] )
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
    deps_test (mli_only @@ deps 1)
  )
    &&
  ( Sys.chdir "../stops";
    deps_test (ml_only ["a.ml", ["B"; "C"; "D"; "E"; "F"]
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
                       ] )
  )
    && (
      Sys.chdir "..";
      try
        deps_test (ml_only ["self_cycle.ml", ["Self_cycle"] ]) && false
      with
        S.Cycle (_,units) ->
          let open Solver.Failure in
          let map = analysis units in
          let cmap = categorize map in
          let cmap = normalize map cmap in
          let errs = Map.bindings cmap in
          let r = List.map fst errs = [ Cycle "Self_cycle" ] in
          if not r then
            ( Solver.Failure.pp map Pp.std cmap; r )
          else
            r
    )

let () =
  if result then
    Format.printf "Success.\n"
  else
    Format.printf "Failure.\n"
