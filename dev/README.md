# dev/

Development tooling. Excluded from the built package (`.Rbuildignore`). Run every script from the repo root.
Scripts marked "real data" need `WISEAPP_DATA_PATH` set in `.Renviron`; run them from R or Positron, because the shell does not load it.

| Path | What | Real data |
|---|---|---|
| `run_dev.R` | Document, reload and run the app (Golem entry) | no |
| `00_make_manifest.R` | Regenerate `manifest.json` for Posit Connect | no |
| `agents_check.R` | Check the paths, functions and sizes named in agent instructions; runs in CI | no |
| `docs_check.R`, `docs_index.R` | Validate the pages of `docs/`; rebuild `docs/index.yml` | no |
| `make_math_cache.R` | Rebuild `inst/math_cache.json` after a `wise_math()` change | no |
| `ui_drive.R` | Drive the running app in headless Chrome (skill `wise-ui-check`) | no |
| `parity_enso.R` | Check that the ENSO labels change no numbers | fixture or real |
| `forecast/` | Build the seasonal forecast fixture; check a data root's forecast files | real |
| `bench/` | Benchmark harnesses (skill `wise-benchmark`); `bench/lib/` holds helpers that tests also load | mostly |
| `fixtures/` | Git-ignored output of `forecast/make_fixture_forecast.R` | n/a |

The batch parity scripts live in `batch/parity/`.
