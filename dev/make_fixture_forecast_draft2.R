# Build a synthetic draft-2 seasonal forecast data root for app development and tests.
#
# The root is a set of symlinks to the real data root (survey, H3 and historical
# weather files) plus its own hazard/weather/forecasts/<code>/ directory. The real
# data root is only read; nothing is written to it. Output goes to dev/fixtures/
# (gitignored) unless `out` is given.
#
# Usage (from the repo root):
#   Rscript dev/make_fixture_forecast_draft2.R [code] [init] [out]
#   source("dev/make_fixture_forecast_draft2.R"); make_fixture_forecast_draft2()
#
# Schema: wise-app-data README, "Gridded forecasts (draft-2 schema)". Observed
# context rows use the ERA5-Land file where it has data (source "era5land") and
# climatology plus fixed noise beyond it (source "era5land_t"). Forecast rows are
# the calendar-month climatology plus a member shift and cell noise.

make_fixture_forecast_draft2 <- function(
  code = "BFA",
  init = as.Date("2026-10-01"),
  out = file.path("dev", "fixtures", "data_root"),
  data_path = Sys.getenv("WISEAPP_DATA_PATH"),
  n_leads = 6L,
  n_members = 51L,
  context_months = 12L,
  anomaly = 1.0,
  member_sd = 0.4,
  n_cells = NA_integer_,
  seed = 1L
) {
  init <- as.Date(init)
  stopifnot(nzchar(data_path), dir.exists(data_path), format(init, "%d") == "01")
  hist_file <- file.path(data_path, "hazard/weather/historical", code, paste0(code, "_era5land.parquet"))
  stopifnot(file.exists(hist_file))

  # Data root of symlinks, except for hazard/weather/forecasts.
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  is_link <- function(path) isTRUE(nzchar(Sys.readlink(path)) && !is.na(Sys.readlink(path)))
  link_children <- function(from, to) {
    dir.create(to, recursive = TRUE, showWarnings = FALSE)
    for (x in list.files(from, all.files = FALSE)) {
      dest <- file.path(to, x)
      if (!file.exists(dest) && !is_link(dest)) file.symlink(file.path(from, x), dest)
    }
  }
  link_children(data_path, out)
  for (sub in c("hazard", "hazard/weather")) {
    path <- file.path(out, sub)
    if (is_link(path)) {
      unlink(path)
      dir.create(path, showWarnings = FALSE)
      link_children(file.path(data_path, sub), path)
    }
  }
  fc_dir <- file.path(out, "hazard/weather/forecasts", code)
  if (is_link(file.path(out, "hazard/weather/forecasts"))) {
    unlink(file.path(out, "hazard/weather/forecasts"))
  }
  dir.create(fc_dir, recursive = TRUE, showWarnings = FALSE)

  stamp <- format(init, "%Y%m%d")
  run_id <- paste0(code, "_c3s_ecmwf_seas51_", stamp)
  data_file <- file.path(fc_dir, paste0(run_id, ".parquet"))
  manifest_file <- file.path(fc_dir, paste0(run_id, ".json"))

  set.seed(seed)
  shifts <- data.frame(member = seq_len(n_members) - 1L, shift = stats::rnorm(n_members, anomaly, member_sd))
  forecast_months <- seq(init, by = "month", length.out = n_leads)
  context <- seq(init, by = "-1 month", length.out = context_months + 1L)[-1L]
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  duckdb::duckdb_register(con, "shifts", shifts)
  duckdb::duckdb_register(con, "months", data.frame(
    timestamp = c(sort(context), forecast_months),
    kind = rep(c("context", "forecast"), c(length(context), n_leads))
  ))
  cell_filter <- if (is.na(n_cells)) "" else sprintf("WHERE rank_h3 <= %d", as.integer(n_cells))
  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE hist AS SELECT CAST(h3 AS BIGINT) AS h3, CAST(timestamp AS DATE) AS timestamp, t
      FROM read_parquet('%s')", hist_file))
  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE cells AS
      SELECT h3 FROM (SELECT h3, row_number() OVER (ORDER BY h3) AS rank_h3 FROM (SELECT DISTINCT h3 FROM hist)) %s",
    cell_filter))
  DBI::dbExecute(con, "
    CREATE TEMP TABLE clim AS
      SELECT h3, month(timestamp) AS mon, avg(t) AS t_clim
      FROM hist WHERE year(timestamp) BETWEEN 1991 AND 2020 GROUP BY 1, 2")
  # Hash-based noise: stable across runs and independent of thread scheduling.
  noise <- function(expr, scale) sprintf("((hash(%s) %% 20000) / 10000.0 - 1.0) * %f", expr, scale)
  sql <- sprintf("
    COPY (
      SELECT CAST(s.member AS INTEGER) AS member, c.h3 AS h3, m.timestamp AS timestamp,
        CAST(1 + (year(m.timestamp) * 12 + month(m.timestamp)) - (year(DATE '%1$s') * 12 + month(DATE '%1$s'))
          AS INTEGER) AS lead_month,
        CASE WHEN m.kind = 'forecast' THEN 'forecast' WHEN h.t IS NOT NULL THEN 'era5land' ELSE 'era5land_t' END
          AS source,
        CAST(CASE
          WHEN m.kind = 'forecast' THEN k.t_clim + s.shift + %2$s
          WHEN h.t IS NOT NULL THEN h.t
          ELSE k.t_clim + %3$s END AS DOUBLE) AS t
      FROM cells c
      CROSS JOIN months m
      CROSS JOIN shifts s
      JOIN clim k ON k.h3 = c.h3 AND k.mon = month(m.timestamp)
      LEFT JOIN hist h ON h.h3 = c.h3 AND h.timestamp = m.timestamp
      ORDER BY member, h3, timestamp
    ) TO '%4$s.part' (FORMAT parquet, COMPRESSION zstd)",
    format(init), noise("c.h3 || '|' || m.timestamp || '|' || s.member", 0.3),
    noise("c.h3 || '|' || m.timestamp", 0.5), data_file)
  DBI::dbExecute(con, sql)
  file.rename(paste0(data_file, ".part"), data_file)

  chk <- DBI::dbGetQuery(con, sprintf("
    SELECT count(*) AS n, count(DISTINCT h3) AS cells, count(DISTINCT member) AS members,
      count(*) - count(DISTINCT (member, h3, timestamp)) AS duplicate_keys,
      sum(CASE WHEN t IS NULL OR NOT isfinite(t) THEN 1 ELSE 0 END) AS n_missing
    FROM read_parquet('%s')", data_file))
  sha <- function(f) digest::digest(file = f, algo = "sha256")
  # Synthetic hindcast skill (schema of forecast_skill_columns in wise-app-data): skill fades with lead.
  skill_rel <- file.path("skill", sprintf("ecmwf_seas51_%02d_1993_2016.parquet", as.integer(format(init, "%m"))))
  dir.create(file.path(fc_dir, "skill"), showWarnings = FALSE)
  acc <- c(0.55, 0.35, 0.2, 0.1, 0.05, 0.02)[seq_len(n_leads)]
  acc_d <- acc - 0.05
  crpss <- c(0.2, 0.08, 0.01, -0.03, -0.05, -0.08)[seq_len(n_leads)]
  skill <- data.frame(
    init_month = as.integer(format(init, "%m")), lead_month = seq_len(n_leads), level = "country",
    acc = acc, acc_detrended = acc_d, acc_detrended_lo = acc_d - 0.3, acc_detrended_hi = acc_d + 0.3,
    crpss = crpss, n_years = 24L, skill_flag = "none"
  )
  # The agreed rule (wise-app-data, 2026-11-02, "balanced"): useful = acc_detrended >= 0.40 and crpss > 0;
  # weak = not useful, acc_detrended >= 0.20 and crpss >= 0; none otherwise.
  skill$skill_flag <- ifelse(acc_d >= 0.40 & crpss > 0, "useful",
    ifelse(acc_d >= 0.20 & crpss >= 0, "weak", "none"))
  duckdb::duckdb_register(con, "skill_tbl", skill)
  DBI::dbExecute(con, sprintf("COPY skill_tbl TO '%s' (FORMAT parquet, COMPRESSION zstd)", file.path(fc_dir, skill_rel)))
  manifest <- list(
    schema_version = "draft-2", status = "draft", experimental = TRUE, synthetic = TRUE,
    product = "seasonal", lead_unit = "month", run_id = run_id, model = "ecmwf_seas51", system = 51L,
    initialized_at = format(init), reference_years = 1993:2016, leads = seq_len(n_leads),
    members = list(first = 0L, last = n_members - 1L), n_members = n_members,
    valid_months = format(forecast_months),
    # As the pipeline writes it: a count with the first and last context month and each month's source.
    context_months = list(n = context_months, first = format(min(context)), last = format(max(context)),
      sources = stats::setNames(as.list(ifelse(context <= as.Date("2025-12-01"), "era5land", "era5land_t")),
        format(context))),
    variables = "t", units = list(t = "degrees_C"),
    h3 = list(resolution = 6L, type = "int64", mapping = "nearest_source_coordinate_to_h3_centroid"),
    adjustment = "additive_mean_bias_only",
    adjustment_formula = "t = era5land_mean + (t_raw - hindcast_mean)",
    observed_through = format(seq(init, by = "-1 month", length.out = 2L)[2L]),
    output_sha256 = stats::setNames(list(sha(data_file), sha(file.path(fc_dir, skill_rel))),
      c(basename(data_file), skill_rel)),
    skill_file = skill_rel,
    input_sha256 = list(historical = sha(hist_file)),
    checks = as.list(chk),
    limitations = "Synthetic fixture: climatology plus noise, no skill",
    created_at = format(Sys.time(), tz = "UTC", usetz = TRUE)
  )
  writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE, null = "null"), manifest_file)

  entry <- data.frame(
    id = format(init, "%Y-%m"), product = "seasonal", lead_unit = "month",
    label = format(init, "%B %Y"), model = "ECMWF SEAS5", init = format(init),
    released = format(init + 5L), next_release = format(seq(init, by = "month", length.out = 2L)[2L] + 5L),
    n_members = n_members, n_leads = n_leads, observed_through = manifest$observed_through,
    context_months = context_months, context_source = "era5land;era5land_t", variables = "t",
    adjustment = manifest$adjustment,
    file = paste0("hazard/weather/forecasts/", code, "/", basename(data_file)),
    data_sha256 = sha(data_file), manifest_sha256 = sha(manifest_file),
    status = "draft", data_version = "fixture-draft-2"
  )
  cat_file <- file.path(fc_dir, "catalogue.csv")
  old <- if (file.exists(cat_file)) utils::read.csv(cat_file, colClasses = "character") else NULL
  if (!is.null(old)) old <- old[old$id != entry$id, , drop = FALSE]
  utils::write.csv(rbind(old, entry[names(entry)]), cat_file, row.names = FALSE)
  message("Fixture data root: ", normalizePath(out), " (", chk$n, " rows, ", chk$cells, " cells)")
  invisible(list(root = normalizePath(out), data_file = data_file, manifest = manifest_file, checks = chk))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  make_fixture_forecast_draft2(
    code = if (length(args) >= 1L) args[[1L]] else "BFA",
    init = if (length(args) >= 2L) as.Date(args[[2L]]) else as.Date("2026-10-01"),
    out = if (length(args) >= 3L) args[[3L]] else file.path("dev", "fixtures", "data_root")
  )
}
