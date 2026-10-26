---
name: wise-release
description: >
  Prepare a WISE-APP release or deploy to Posit Connect: version bump, manifest,
  DuckDB pin and bundled extension checks, CI gates, and what needs the user's
  go-ahead. Prepares and verifies; it never pushes or deploys.
when_to_use: >
  When the user asks to bump the version, cut a release, regenerate the
  manifest, upgrade DuckDB or a dependency, or check that the app is ready to
  deploy.
user-invocable: true
allowed-tools: Read Grep Glob Edit Bash
argument-hint: "[version, or 'manifest' | 'duckdb' | 'check']"
---

# Releasing or deploying WISE-APP

Deployment settings, resource limits and environment variables are in
`DEPLOYMENT.md`. Pushing, deploying and uploading need the user's explicit
go-ahead each time; approval for one does not extend to the next. Never print
credentials or `.Renviron`.

## 1. Version

The version is in two places that must match: `Version:` in `DESCRIPTION` and
`golem_version` in `inst/golem-config.yml` (`dev/agents_check.R` checks this).
After a bump, regenerate the manifest (section 3).

## 2. Readiness checks

Run with the tree quiet and committed (the manifest is built from `HEAD`):

1. `git status`: no unrelated changes in the release.
2. `devtools::document()` with roxygen2 7.3.3; the `NAMESPACE` diff is only
   what you meant.
3. `devtools::test()` (4 to 6 minutes, run in the background) and
   `devtools::check()`.
4. `Rscript tests/e2e/smoke.R` (about 5 minutes; Chrome, `arrow` and the
   DuckDB `h3` extension). `main` requires the `e2e-smoke` status check.
5. Real-data parity per release, not run in CI: `dev/batch_parity_bfa.R`,
   `dev/batch_parity_bfa_models.R`, `dev/batch_parity_bfa_sim.R`,
   `dev/batch_parity_bfa_policy.R` (need `WISEAPP_DATA_PATH`, read in R).
6. A browser pass of the changed screens (skill `wise-ui-check`).
7. `Rscript dev/docs_check.R` and `Rscript dev/agents_check.R`.

State what was not run.

## 3. Manifest

`Rscript dev/00_make_manifest.R` writes `manifest.json` from `git archive HEAD`
(committed content only), for the app files `app.R`, `R/`, `src/`, `inst/`,
`DESCRIPTION` and `NAMESPACE`, and filters to the runtime dependency closure
(no Suggests). Re-run it, and commit the result, after any change to those
files or to dependencies. Documentation, `docs/`, `review/`, `dev/` and tests
are not in the bundle, so changing them needs no regeneration.

## 4. DuckDB upgrade

The bundled extensions (`inst/duckdb_extensions/`: `h3` and `httpfs`, as
`.gz`) are built for one exact DuckDB version, and the app refuses a mismatch
or a wrong checksum (`.duck_check_bundled_ext()` in `R/fct_load_data.R`). To
upgrade, change together:

- `duckdb (== X)` in `DESCRIPTION`;
- `.DUCKDB_BUNDLE_VERSION` and `.DUCKDB_BUNDLE_SHA256` in `R/fct_load_data.R`;
- the two binaries, rebuilt for that version.

How the binaries are built is not recorded in this repository: ask the user
for the procedure and the source of the files before starting, and do not
substitute binaries of another version. Then rerun the batch fixture and smoke
tests, the manifest and the parity scripts. Decisions on staying on a version
(R2-OPS-05) are in the tracker's archive.

## 5. Deploy

Target is Posit Connect (git-backed deployment). Before the user deploys:
manifest committed, `DEPLOYMENT.md` settings reviewed for the target (data
source, allowlists, memory and thread limits), and the CARTO host reachable for
maps. Do not push, merge to `main` or deploy yourself. Report the commit to
deploy, the checks run, and the open items from the tracker's "Waiting on the
user" (for example CR-SEC-09 staging needs a go-ahead before any deployment).

## Report

Version, commit, each check with its result, what was skipped and why, and
what the user must do next.

## Traps

- A manifest built before committing describes the previous commit.
- Upgrading R packages changes the manifest closure; do it deliberately.
- `dev` is deliberately unprotected; `main` requires `e2e-smoke`.
