A note to the examiners on code credit:
- `TooobaWrapper/filter_known_warnings` was generated with ChatGPT and I take no credit for it. Please imagine it was created by another human;
- `TooobaWrapper/Toooba` is a submodule containing my fork of Toooba; and
- `ChampSimWrapper/ChampSim` is a submodule containing my fork of another Part II student's (Blind Grading Number 2373A) fork of ChampSim -- our project were in no way collaborative as this forked work was done before the projects began.

The licenses can be found in `TooobaWrapper/Toooba` and `ChampSimWrapper/ChampSim`. I have included notices on modified files or added files/directories indicating such status.


Use `BSC_COMPILATION_FLAGS` in `Include_RISCY_Config.mk` to decide which predictors to use, then do `make -C TooobaWrapper/Toooba/builds/RV64ACDFIMSU_Toooba_bluesim clean` after changing the config.
E.g.,
```
-D ALTERNATE_IFC_NAP \
-D ALTERNATE_IFC_NAP_PARAM \
-D ALTERNATE_IFC_BDP \
-D ALTERNATE_IFC_BDP_PARAM
```
will use my alternative interfaces for branch direction prediction (BDP) and next-address prediction(NAP -- similar to BTB). Furthermore, it will use instantiations of the parameterisable Gselect predictor.

To run CoreMark, do `TooobaWrapper/try_coremark.sh`.

To run benchmarks, \[TODO\].

To run RISC-V ISA tests:
```
make -C TooobaWrapper/Toooba/builds/RV64ACDFIMSU_Toooba_bluesim isa_tests
```

To run MiBench benchmarks:
```
make -C TooobaWrapper/Toooba/builds/RV64ACDFIMSU_Toooba_bluesim benchmarks
```

To run unit tests for my utilities:
```
make -C tests
```
(You can also use `make -C tests TEST=testname` to run `testname.bsv` only.)
