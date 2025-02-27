#!/usr/bin/env python3

# This file was generated with ChatGPT.

import subprocess
import sys
import argparse
import re

def load_baseline(baseline_file):
    """Load known warnings from a baseline stderr file."""
    try:
        with open(baseline_file, "r") as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"Warning: Baseline file '{baseline_file}' not found. Proceeding without filtering.", file=sys.stderr)
        return set()

    known_warnings = set()
    current_warning = []

    for line in lines:
        if line.startswith("Warning: "):  # New warning starts
            if current_warning:
                known_warnings.add("\n".join(current_warning))
            current_warning = [line.rstrip()]
        elif re.match(r"^\s+", line):  # Continuation of the warning (any leading whitespace)
            current_warning.append(line.rstrip())
        else:  # End of a warning block
            if current_warning:
                known_warnings.add("\n".join(current_warning))
                current_warning = []
    
    if current_warning:
        known_warnings.add("\n".join(current_warning))

    return known_warnings

def filter_stderr(command, baseline_file):
    """Run a command and filter stderr based on a baseline file."""
    known_warnings = load_baseline(baseline_file)
    process = subprocess.Popen(command, stderr=subprocess.PIPE, stdout=sys.stdout, text=True)

    current_warning = []
    
    while True:
        line = process.stderr.readline()
        if not line:
            break  # No more stderr output

        line_strip = line.rstrip()  # Removes only trailing newline but keeps leading spaces/tabs

        if line.startswith("Warning: "):  # New warning starts
            if current_warning:
                warning_text = "\n".join(current_warning)
                if warning_text not in known_warnings:
                    print(warning_text, file=sys.stderr)
            current_warning = [line_strip]
        elif re.match(r"^\s+", line):  # Continuation of the warning (any leading whitespace)
            current_warning.append(line_strip)
        else:  # Not a warning or new output
            if current_warning:
                warning_text = "\n".join(current_warning)
                if warning_text not in known_warnings:
                    print(warning_text, file=sys.stderr)
                current_warning = []
            print(line, end="", file=sys.stderr)  # Print non-warning stderr output

    if current_warning:
        warning_text = "\n".join(current_warning)
        if warning_text not in known_warnings:
            print(warning_text, file=sys.stderr)

    process.wait()
    return process.returncode

def main():
    parser = argparse.ArgumentParser(description="Filter known warnings from stderr in real-time.")
    parser.add_argument("command", nargs="+", help="The command to run.")
    parser.add_argument("-b", "--baseline", required=True, help="Baseline stderr file with known warnings.")
    
    args = parser.parse_args()
    returncode = filter_stderr(args.command, args.baseline)
    sys.exit(returncode)

if __name__ == "__main__":
    main()