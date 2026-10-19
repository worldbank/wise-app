# Run the batch: Rscript run.R
#
# Needs the data folder in WISEAPP_DATA_PATH (for example in ~/.Renviron).
# Set the number of parallel workers here; each worker gets its share of the
# cores (and of WISEAPP_BATCH_MEMORY_GB when set).

workers <- 2

Sys.setenv(WISEAPP_BATCH_WORKERS = workers)

# Preview the runs first: one row per run, with the stage ids that decide
# which work is shared.
print(wiseapp::wise_spec_expand("spec.yaml"))

targets::tar_make()

# Results are in results/: runs.parquet, tables/, failures.parquet, manifest.json.
print(arrow::read_parquet("results/failures.parquet"))
