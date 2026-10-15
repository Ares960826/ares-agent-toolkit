#!/usr/bin/env bash
# Parse a directory locally using the shared MinerU 4 wrapper.
# Usage: batch-local.sh INPUT_DIR [OUTPUT_DIR] [--tier standard] [options]
set -euo pipefail
if [[ $# -lt 1 || "$1" == -h || "$1" == --help ]]; then
  printf '%s\n' 'batch-local.sh INPUT_DIR [OUTPUT_DIR] [--tier standard|basic|advanced|flash] [options]'
  exit 0
fi
input="$1"; shift
[[ -d "$input" ]] || { echo "batch-local: directory not found: $input" >&2; exit 1; }
output="${input%/}_md"
if [[ $# -gt 0 && "$1" != -* ]]; then output="$1"; shift; fi
exec "${HOME}/.local/bin/pdf2md" "$input" "$output" "$@"
