let signature= let open Module in  let open Sig in 
of_list [M {name="Unix"; origin=Unit {source=Special "stdlib/unix"; file=["Unix"]}; args=[]; signature=of_list 
           [M {name="LargeFile"; origin=Submodule; args=[]; signature=empty}]}; 
        M {name="UnixLabels"; origin=Unit {source=Special "stdlib/unix"; file=["UnixLabels"]}; args=[]; signature=of_list 
          [M {name="LargeFile"; origin=Submodule; args=[]; signature=empty}]}]
