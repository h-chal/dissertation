To run ChampSim with a given Bluespec SystemVerilog predictor, called `x`:
- Name the predictor in `ChampSimWrapper/config.json`
- Ensure that `branch_predictors/x/x.bsv` exists
```
git submodule update --init --recursive

cd ChampSimWrapper/ChampSim
vcpkg/bootstrap-vcpkg.sh
vcpkg/vcpkg install
cd ../..

wget -P traces/DPC-3 https://dpc3.compas.cs.stonybrook.edu/champsim-traces/speccpu/600.perlbench_s-210B.champsimtrace.xz

ChampSimWrapper/try_champsim_bsv_branch.sh
```
