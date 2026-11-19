# WISE-APP batch project

This folder runs WISE-APP without the interface for a grid of samples and
settings, and writes tidy result tables.

1. Point `WISEAPP_DATA_PATH` at the data folder.
2. Edit `spec.yaml`.
3. Preview the runs: `wiseapp::wise_spec_expand("spec.yaml")`.
4. Run: `Rscript run.R` (or `targets::tar_make()`).
5. Read the results from `results/`:

```r
arrow::read_parquet("results/runs.parquet")
arrow::open_dataset("results/tables/variable_stats") |> dplyr::collect()
```

## Reproducibility

Pin the software once, before the first run:

```r
renv::init()
renv::install("worldbank/wise-app@<tag or commit>")
renv::snapshot()
```

Keep `renv.lock`, `spec.yaml`, `run.R` and `_targets.R` with the results.
`results/manifest.json` records the `wiseapp` version and commit, the R and
`duckdb` versions, the hash of `renv.lock` and the SHA-256 of the survey files
the runs read (local data folders). To check another machine against a run,
restore the lock (`renv::restore()`), set `WISEAPP_DATA_PATH` and run
`Rscript check_reproducibility.R`. Run `Rscript run.R` to reproduce the tables.

Changing `spec.yaml` and running again recomputes only what the change
touches. `results/failures.parquet` lists stages that failed and the runs
they affect. The user guide is `batch/README.md` in the WISE-APP repository.
