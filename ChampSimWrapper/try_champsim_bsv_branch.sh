#!/bin/bash
scriptDir=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")
cd "$scriptDir"/ChampSim

WARMUP_INSTRUCTIONS=200000
SIMULATION_INSTRUCTIONS=500000
TRACE="../../traces/DPC-3/600.perlbench_s-210B.champsimtrace.xz"

CONFIG_FILE="../config.json"
# File to store the last modification time for CONFIG_FILE.
TIMESTAMP_FILE="../.config.json.timestamp"

# Create a symlink to branch_predictors directory. This is removed at the end.
ln -fs ../../../../branch_predictors branch/bsv_predictor/Predictors
# A symlink for config. This is because having the config file higher in the file tree causes errors.
ln -fs "$CONFIG_FILE" symlink_config.json

CONFIG_COMMAND="./config.sh symlink_config.json"
CHAMPSIM_COMMAND="make > /dev/null && bin/champsim --warmup-instructions $WARMUP_INSTRUCTIONS --simulation-instructions $SIMULATION_INSTRUCTIONS $TRACE \
| grep -m 1 \"Branch Prediction Accuracy\" | awk '{print \"Conditional Branch Accuracy: \" \$6}'"

UNMODIFIED_COMMAND="$CHAMPSIM_COMMAND"
MODIFIED_COMMAND="echo \"Configuration change detected; reconfiguring\" && $CONFIG_COMMAND && $CHAMPSIM_COMMAND"


if [[ ! -e "$CONFIG_FILE" ]]; then
    echo "Error: Config file does not exist"
    # Remove the symlinks.
    unlink branch/bsv_predictor/Predictors
    unlink symlink_config.json
    exit 1
fi

CURRENT_MOD_TIME=$(stat -c %Y "$CONFIG_FILE")

if [[ -e "$TIMESTAMP_FILE" ]]; then
    LAST_MOD_TIME=$(cat "$TIMESTAMP_FILE")

    if [[ "$CURRENT_MOD_TIME" -eq "$LAST_MOD_TIME" ]]; then
        # Config unmodified since last run.
        eval "$UNMODIFIED_COMMAND"
    else
        # Config modified since last run.
        eval "$MODIFIED_COMMAND"
    fi
else
    # Timestamp file doesn't exist; treat as modified.
    eval "$MODIFIED_COMMAND"
fi

# Update the timestamp file with the current modification time.
echo "$CURRENT_MOD_TIME" > "$TIMESTAMP_FILE"

# Remove the symlinks.
unlink branch/bsv_predictor/Predictors
unlink symlink_config.json
