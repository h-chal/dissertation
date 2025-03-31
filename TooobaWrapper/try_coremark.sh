# TODO
# Configure which predictor used. ProcConfig.bsv. try putting it in a less central file for faster make
# Recompile when config changed or predictor source changed

set -e
trap 'notify-send "Toooba CoreMark failed."' ERR

cd TooobaWrapper

# Filter known warnings from stderr and ignore stdout.
./filter_known_warnings.py -b baseline_make_err.txt -- \
make -C Toooba/builds/RV64ACDFIMSU_Toooba_bluesim compile simulator > /dev/null

ln -fs coremark_gcc.hex Mem.hex

Toooba/builds/RV64ACDFIMSU_Toooba_bluesim/exe_HW_sim > /tmp/toooba_output.txt

tail --lines=1 /tmp/toooba_output.txt | xargs

notify-send "Toooba CoreMark finished."