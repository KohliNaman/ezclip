#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUTPUT=${1:-"$ROOT/build/benchmarks/library-$(date +%Y%m%d-%H%M%S).json"}
mkdir -p "$(dirname "$OUTPUT")"
python3 "$ROOT/Scripts/benchmark_library.py" --count 50000 --output "$OUTPUT"
echo "benchmark written: $OUTPUT"
