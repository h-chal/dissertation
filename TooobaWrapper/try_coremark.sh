#!/bin/bash
set -e
trap 'notify-send "Toooba CoreMark failed."' ERR

cd TooobaWrapper

# Recompile
./filter_known_warnings.py -b baseline_make_err.txt -- \
make -C Toooba/builds/RV64ACDFIMSU_Toooba_bluesim compile simulator > /dev/null

ln -fs coremark_gcc.hex Mem.hex

SIM_CMD="Toooba/builds/RV64ACDFIMSU_Toooba_bluesim/exe_HW_sim"

# Start simulation in background
TMP_OUT=$(mktemp)
$SIM_CMD > "$TMP_OUT" 2>&1 &

SIM_PID=$!

# Monitor for instret:188799
while sleep 0.2; do
    if grep -q "instret:188799" "$TMP_OUT"; then
        kill "$SIM_PID"
        wait "$SIM_PID" 2>/dev/null || true
        LINE=$(grep "instret:188799" "$TMP_OUT" | tail -n 1)
        CYCLES=$(echo "$LINE" | awk '{print $NF}')
        echo "Cycles: $CYCLES"
        break
    fi
done

notify-send "Toooba CoreMark finished."
