#!/usr/bin/env bash
# batch-local.sh — parse a whole folder of documents LOCALLY with MinerU.
# No token, no cloud — the local fallback for "batch but keep it on-machine".
#
#   bash batch-local.sh <input_dir> [output_dir] [extra mineru args...]
#
# Examples:
#   bash batch-local.sh ~/papers
#   bash batch-local.sh ~/papers ~/papers_md
#   bash batch-local.sh ~/scans ~/scans_md -m ocr
#
set -euo pipefail

if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0
fi

IN="$1"; shift
[[ -d "$IN" ]] || { echo "batch-local: input dir not found: $IN" >&2; exit 1; }
OUT=""
if [[ $# -ge 1 && "${1:0:1}" != "-" ]]; then OUT="$1"; shift; fi
[[ -n "$OUT" ]] || OUT="${IN%/}_md"
mkdir -p "$OUT"

command -v mineru >/dev/null 2>&1 || { echo "batch-local: mineru not installed (run setup.sh)" >&2; exit 1; }
export MINERU_MODEL_SOURCE="${MINERU_MODEL_SOURCE:-modelscope}"

# Default to pipeline backend unless caller passed -b/--backend.
have_b=0; for a in "$@"; do case "$a" in -b|--backend) have_b=1;; esac; done
[[ $have_b -eq 1 ]] || set -- -b pipeline "$@"

# MinerU accepts a directory as -p and parses every supported file in it.
echo "batch-local: $IN -> $OUT  (source=$MINERU_MODEL_SOURCE)" >&2
mineru -p "$IN" -o "$OUT" "$@"
echo "batch-local: done. Markdown under $OUT" >&2
