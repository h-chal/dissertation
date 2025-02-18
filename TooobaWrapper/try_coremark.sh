# TODO
# Configure which predictor used. ProcConfig.bsv. try putting it in a less central file for faster make
# Recompile when config changed or predictor source changed


cd TooobaWrapper

make -C Toooba/builds/RV64ACDFIMSU_Toooba_bluesim -j$(nproc) compile simulator > /dev/null

ln -fs coremark_gcc.hex Mem.hex

Toooba/builds/RV64ACDFIMSU_Toooba_bluesim/exe_HW_sim > /tmp/toooba_output.txt

tail --lines=1 /tmp/toooba_output.txt | xargs
