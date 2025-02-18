echo "Please ensure you have recompiled Toooba if any changes are made to it or to the predictor in use."

# TODO
# Configure which predictor used. ProcConfig.bsv. try putting it in a less central file for faster make
# Recompile when config changed or predictor source changed


cd TooobaWrapper

ln -fs coremark_gcc.hex Mem.hex

Toooba/builds/RV64ACDFIMSU_Toooba_bluesim/exe_HW_sim > /tmp/toooba_output.txt

tail --lines=1 /tmp/toooba_output.txt | xargs
