#!/bin/bash

# This script makes and runs ChampSim with the predictor defined in config.json.
# It ignores any output apart from errors and the conditional branch accuracy.
# If run with argument `verbose`, the full ChampSim output is given.

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo " -h, --help               Display this help message"
    echo " -v, --verbose            See all output from ChampSim"
    echo " -w NUM, --warmup=NUM     Use NUM warmup instructions"
    echo " -s NUM, --simulation=NUM Use NUM simulation instructions (count towards branch accuracy)"
    echo " -t FILE, --trace=FILE    Use FILE (relative to project root) as the trace"
    echo " -c FILE, --config=FILE   Use FILE (relative to prject root) to configure ChampSim"
}

# Default values
VERBOSE=false
WARMUP_INSTRUCTIONS=200000
SIMULATION_INSTRUCTIONS=500000
TRACE="ChampSimWrapper/traces/DPC-3/600.perlbench_s-210B.champsimtrace.xz"
CONFIG_FILE="ChampSimWrapper/config.json"

while [ $# -gt 0 ]; do
    case $1 in
        -h | --help)
            usage
            exit 0
            ;;
        -v | --verbose)
            VERBOSE=true
            ;;
        -w)
            if [[ ! -z "$2" && "$2" != -* ]]; then
                WARMUP_INSTRUCTIONS="$2"
                shift
            else
                usage
                exit 1
            fi
            ;;
        --warmup=*)
            if [[ -n ${1#*=} ]]; then
                SIMULATION_INSTRUCTIONS="${1#*=}"
            else
                usage
                exit 1
            fi
            ;;
        -s)
            if [[ ! -z "$2" && "$2" != -* ]]; then
                SIMULATION_INSTRUCTIONS="$2"
                shift
            else
                usage
                exit 1
            fi
            ;;
        --simulation=*)
            if [[ -n ${1#*=} ]]; then
                SIMULATION_INSTRUCTIONS="${1#*=}"
            else
                usage
                exit 1
            fi
            ;;
        -t)
            if [[ ! -z "$2" && "$2" != -* ]]; then
                TRACE="$2"
                shift
            else
                usage
                exit 1
            fi
            ;;
        --trace=*)
            if [[ -n ${1#*=} ]]; then
                TRACE="${1#*=}"
            else
                usage
                exit 1
            fi
            ;;
        -c)
            if [[ ! -z "$2" && "$2" != -* ]]; then
                CONFIG_FILE="$2"
                shift
            else
                usage
                exit 1
            fi
            ;;
        --config=*)
            if [[ -n ${1#*=} ]]; then
                CONFIG_FILE="${1#*=}"
            else
                usage
                exit 1
            fi
            ;;
        *)
            usage
            exit 1
            ;;
    esac
    shift
done

TRACE=$(realpath "$TRACE")
CONFIG_FILE=$(realpath "$CONFIG_FILE")

scriptDir=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")
cd "$scriptDir"/ChampSim

# File to store the last modification time for CONFIG_FILE.
TIMESTAMP_FILE="$(dirname "$CONFIG_FILE")/.$(basename "$CONFIG_FILE").timestamp"

# Create a symlink to branch_predictors directory. This is removed at the end.
test ! -e branch/bsv_predictor/Predictors && ln -s ../../../../branch_predictors branch/bsv_predictor/Predictors
# A symlink for config. This is because having the config file higher in the file tree causes errors.
ln -s "$CONFIG_FILE" symlink_config.json

CONFIG_COMMAND="./config.sh symlink_config.json"
CHAMPSIM_COMMAND="make > /dev/null && bin/champsim --warmup-instructions $WARMUP_INSTRUCTIONS --simulation-instructions $SIMULATION_INSTRUCTIONS $TRACE"
PARSE_OUTPUT_COMMAND="| grep -m 1 \"Branch Prediction Accuracy\" | awk '{print \"Conditional Branch Accuracy: \" \$6}'"
if [ "$VERBOSE" = false ]; then
    CHAMPSIM_COMMAND="$CHAMPSIM_COMMAND$PARSE_OUTPUT_COMMAND"
fi

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
