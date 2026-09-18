#!/bin/zsh
# Run the Phase 1 Step 2 benchmark with an external peak-RSS measurement.
#
# Usage:
#   WISEAPP_DATA_PATH=/path/to/data \
#   WISEAPP_STEP2_PAYLOAD_MODE=legacy|compact \
#   WISEAPP_STEP2_WEATHER_STORAGE=memory|reference \
#   WISEAPP_STEP2_WEATHER_COLLECT=fast|bounded \
#     dev/run_step2_benchmark.sh
#
# Opt-in Step 3 fixture:
#   WISEAPP_STEP2_INCLUDE_STEP3=1 \
#   WISEAPP_STEP3_POLICIES=covariate,targeted_sp,combined \
#     dev/run_step2_benchmark.sh
#
# Fabricated smoke-only fixture, never production-path evidence:
#   WISEAPP_STEP2_FIXTURE=smoke WISEAPP_STEP2_INCLUDE_STEP3=1 \
#     dev/run_step2_benchmark.sh
#
# The R harness writes structured reports. This wrapper adds the complete
# process-tree measurement from macOS /usr/bin/time -l to console.log.

set -euo pipefail

repo_root="${0:A:h}/.."
output_dir="${WISEAPP_STEP2_OUTPUT_DIR:-$repo_root/dev/outputs/step2-benchmark}"
mkdir -p "$output_dir"

cd "$repo_root"
/usr/bin/time -l Rscript dev/bench_step2.R 2>&1 | tee "$output_dir/console.log"

external_rss_bytes="$(/usr/bin/awk '/maximum resident set size/ { value=$1 } END { print value }' \
  "$output_dir/console.log")"
if [[ -n "$external_rss_bytes" ]]; then
  printf 'scope,metric,value,unit\nbenchmark_process,maximum_resident_set_size,%s,bytes\n' \
    "$external_rss_bytes" > "$output_dir/external_process_metrics.csv"
fi
