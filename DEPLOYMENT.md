# Deployment and runtime settings

Reference for deploying WISE-APP to Posit Connect and for the environment variables that control it. Moved from `ARCHITECTURE.md`.

## Deployment

Target platform: **Posit Connect**. Automatic startup data-source selection is controlled by `WISEAPP_DATA_SOURCE`; see the environment variables below and the deployment scripts for deployment steps.

Runtime egress: the app serves its fonts locally (`inst/app/fonts/`), but the hex map loads its basemap style and tiles from CARTO (`tiles.basemaps.cartocdn.com`, see `inst/app/vendor/hexmap.js`). The server must allow HTTPS to that host for map views; everything else needs only the configured data source.

Bundled DuckDB extensions (`inst/duckdb_extensions/`: `h3` and `httpfs`) are built for DuckDB 2.0.0 (`.DUCKDB_BUNDLE_VERSION` in `R/fct_load_data.R`). `DESCRIPTION` requires `duckdb (>= 2.0.0)`; the engine version (`SELECT version()`, so a development build such as the r-universe 2.0.0.9000 qualifies) must equal that constant, and the binaries are checked against pinned SHA-256 values before they are installed on Connect.

To upgrade DuckDB, rebuild the binaries and update the `DESCRIPTION` minimum, the version constant and the checksums together. The binaries are `linux_amd64` only (the Connect target) and are the official downloads for the pinned version: `httpfs` from `https://extensions.duckdb.org/v<version>/linux_amd64/httpfs.duckdb_extension.gz` and `h3` from `https://community-extensions.duckdb.org/v<version>/linux_amd64/h3.duckdb_extension.gz`. Since DuckDB 2.0, `.duck_con()` opens each connection with `shared_home = FALSE`, so extensions and secrets live in a per-process temp directory and not in a shared `~/.duckdb`. On Connect, `.duck_con()` also sets `allow_unsigned_extensions` (startup-only): DuckDB 2.0 rejects the community-signed `h3` binary when it is installed from a local path ("doesn't have a valid signature"), so the SHA-256 pins above are the integrity check there.

Optional resource limits (unset = package/DuckDB defaults). Every Connect process runs a main R process plus a mirai daemon, each with its own in-memory DuckDB, so cap them on shared hosts:
- `WISEAPP_DUCKDB_MEMORY_LIMIT` (for example `4GB`) and `WISEAPP_DUCKDB_THREADS` (per DuckDB instance); `WISEAPP_DUCKDB_TEMP_DIR` (spill directory, default a per-process temp dir)
- `WISEAPP_THREADS` (fixest and collapse threads)
- `WISEAPP_ASYNC_TIMEOUT_MIN` (Step 2 run limit, default 90), `WISEAPP_ASYNC_STEP3_TIMEOUT_MIN` (Step 3 run and metric jobs, default 90) and `WISEAPP_ASYNC_METADATA_TIMEOUT_SEC` (default 300); `0` disables
- `WISEAPP_ASYNC_STEP3=0` runs the Step 3 policy run and metric decomposition in the main process. By default they run on the shared mirai daemon and read the adopted Step 2 result and the Step 3 policy result from retained qs2 files under `WISEAPP_ASYNC_ARTIFACT_ROOT` (default a per-process temp dir, `retained/`). Budget temp disk per session: about 0.4-0.6 GB at a 3x3 Step 2 payload (BFA 2x2: 178 MB plus 216 MB). The files are removed when the result is replaced and at session end.
- `WISEAPP_STAGE_LOG=0` turns off the one-line-per-run stage log
- Weather disk cache: `WISEAPP_WEATHER_CACHE_DIR` (location, created 0700), `WISEAPP_WEATHER_CACHE_MAX_MB` (LRU budget), `WISEAPP_WEATHER_CACHE_DISABLE=1` (off)
- `WISEAPP_ASYNC_QUEUE_MEMORY_MB` (default 512; `0` disables): the mirai dispatcher's memory cap and the size limit for one job snapshot. A Step 2 or Step 3 snapshot over the cap is refused with a message instead of retried, and queued Step 2 snapshots may total at most twice the cap.
- `WISEAPP_ASYNC_SYNC=1` runs Step 2 and metadata tasks in the main process (debugging only; this removes the async protection)

Data-source allowlists (CR-SEC-02): `WISEAPP_ALLOWED_SOURCES` (comma-separated source types) restricts which sources the app accepts. Unset, a configured `WISEAPP_DATA_SOURCE` is the only enabled type, and on Posit Connect without one only `databricks` is; local and dev runs allow every type. For connections typed into the UI, `WISEAPP_ALLOWED_LOCAL_ROOTS`, `WISEAPP_ALLOWED_BUCKETS` (S3/GCS buckets, Azure containers, Hugging Face repos) and `WISEAPP_ALLOWED_VOLUME_ROOTS` (Databricks volume paths) restrict the location; an unset list does not restrict that field. Values containing control characters or `..` segments are always refused for UI connections. Environment-configured connections are trusted.

Key environment variables for production:
- `WISEAPP_DATA_SOURCE` (automatic source selector: `local`, `s3`, `gcs`, `azure`, `hf`, or `databricks`)
- `WISEAPP_DATA_PATH` (local data backend)
- `DATABRICKS_HOST`, `DATABRICKS_CLIENT_ID`, `DATABRICKS_CLIENT_SECRET`, `DATABRICKS_VOLUME_PATH` (for Databricks backend)
- `S3_BUCKET`, `S3_PREFIX`, `S3_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (for S3)
- `GCS_BUCKET`, `GCS_PREFIX`, `GCS_ACCESS_KEY_ID`, `GCS_SECRET_ACCESS_KEY` (for GCS)
- `AZURE_STORAGE_ACCOUNT`, `AZURE_STORAGE_CONTAINER`, `AZURE_STORAGE_PREFIX`, `AZURE_STORAGE_KEY` or `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID` (for Azure)
- `HF_REPO`, `HF_SUBDIR` (for public Hugging Face datasets)
