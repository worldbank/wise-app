# Local experimental forecast catalogue ----

.forecast_catalogue_runs <- function(connection_params, code) {
  if (is.null(connection_params) || !identical(connection_params$type %||% "local", "local") ||
      length(code) != 1L || is.na(code) || !grepl("^[A-Z]{3}$", code)) return(NULL)
  root <- connection_params$path %||% .default_data_path()
  .assert_connection_allowed(connection_params)
  catalogue <- file.path(root, "hazard/weather/forecasts", code, "catalogue.csv")
  if (!file.exists(catalogue)) return(NULL)
  entries <- utils::read.csv(catalogue, colClasses = "character", stringsAsFactors = FALSE)
  fields <- c("id", "product", "lead_unit", "label", "model", "init", "released", "next_release",
    "n_members", "n_leads", "observed_through", "file", "status", "data_version")
  if (!all(fields %in% names(entries)) || anyNA(entries[fields]) || anyDuplicated(entries$id) ||
      any(!nzchar(unlist(entries[fields])))) {
    stop("Invalid seasonal forecast catalogue.", call. = FALSE)
  }
  runs <- lapply(seq_len(nrow(entries)), function(i) {
    run <- as.list(entries[i, fields])
    if (identical(run$status, "draft") && .on_posit_connect()) return(NULL)
    if (!identical(run$product, "seasonal") || !identical(run$lead_unit, "month") ||
        !run$status %in% c("draft", "complete")) return(NULL)
    expected <- paste0("hazard/weather/forecasts/", code, "/")
    if (!startsWith(run$file, expected) || grepl("\\\\|(^|/)\\.\\.?(/|$)", run$file) ||
        !grepl("^[A-Za-z0-9_/-]+\\.parquet$", run$file)) {
      stop("Invalid seasonal forecast data path.", call. = FALSE)
    }
    data_path <- file.path(root, run$file)
    manifest_path <- sub("\\.parquet$", ".json", data_path)
    # A manifest is written last by the publisher, so incomplete runs are not offered.
    if (!file.exists(data_path) || !file.exists(manifest_path)) return(NULL)
    normalized_root <- normalizePath(root, winslash = "/", mustWork = TRUE)
    if (!.path_under(normalizePath(data_path, winslash = "/", mustWork = TRUE), normalized_root) ||
        !.path_under(normalizePath(manifest_path, winslash = "/", mustWork = TRUE), normalized_root)) {
      stop("Seasonal forecast files must remain within the local data root.", call. = FALSE)
    }
    manifest <- jsonlite::fromJSON(manifest_path, simplifyVector = TRUE)
    if (!identical(manifest$adjustment, "additive_mean_bias_only")) {
      stop("Seasonal forecast must declare the additive mean-bias adjustment.", call. = FALSE)
    }
    for (field in c("init", "released", "next_release", "observed_through")) {
      run[[field]] <- as.Date(run[[field]], format = "%Y-%m-%d")
      if (is.na(run[[field]])) stop("Invalid seasonal forecast date.", call. = FALSE)
    }
    run$n_members <- suppressWarnings(as.integer(run$n_members))
    run$n_leads <- suppressWarnings(as.integer(run$n_leads))
    member_bounds <- as.integer(c(manifest$members$first, manifest$members$last))
    if (length(member_bounds) != 2L || anyNA(member_bounds) || member_bounds[1L] < 0L ||
        member_bounds[2L] < member_bounds[1L] || member_bounds[2L] - member_bounds[1L] > 10000L) {
      stop("Invalid seasonal forecast member range.", call. = FALSE)
    }
    members <- seq.int(member_bounds[1L], member_bounds[2L])
    if (!identical(manifest$product, run$product) || !identical(manifest$lead_unit, run$lead_unit) ||
        !identical(manifest$initialized_at, format(run$init)) ||
        !identical(manifest$observed_through, format(run$observed_through)) ||
        !identical(manifest$status, run$status) ||
        length(manifest$model) != 1L || !nzchar(manifest$model) ||
        length(manifest$run_id) != 1L || !startsWith(manifest$run_id, paste0(code, "_")) ||
        !length(manifest$variables) || any(!manifest$variables %in% .STEP2_FORECAST_VARS) ||
        anyDuplicated(manifest$variables) ||
        !identical(manifest$h3$type, "int64") || !identical(as.integer(manifest$h3$resolution), 6L) ||
        is.na(run$n_members) || run$n_members < 1L || is.na(run$n_leads) || run$n_leads < 1L ||
        !identical(as.integer(manifest$n_members), run$n_members) || length(members) != run$n_members ||
        !identical(as.integer(manifest$leads), seq_len(run$n_leads)) ||
        !identical(as.character(manifest$valid_months),
          format(seq(run$init, by = "month", length.out = run$n_leads)))) {
      stop("Seasonal forecast catalogue and manifest disagree.", call. = FALSE)
    }
    checksum <- manifest$output_sha256[[basename(data_path)]]
    if (length(checksum) != 1L || !identical(checksum,
        digest::digest(file = data_path, algo = "sha256"))) {
      stop("Seasonal forecast data checksum does not match its manifest.", call. = FALSE)
    }
    historical <- file.path(root, "hazard/weather/historical", code, paste0(code, "_era5land.parquet"))
    if (!file.exists(historical) || !identical(manifest$historical_sha256,
        digest::digest(file = historical, algo = "sha256"))) {
      stop("Seasonal forecast observed-weather version does not match the local data.", call. = FALSE)
    }
    run$variables <- as.character(manifest$variables)
    run$members <- as.integer(members)
    run$model_id <- manifest$model
    run$run_id <- manifest$run_id
    run$adjustment <- manifest$adjustment
    run$data_sha256 <- checksum
    run$manifest_sha256 <- digest::digest(file = manifest_path, algo = "sha256")
    run$historical_sha256 <- manifest$historical_sha256
    run$experimental <- isTRUE(manifest$experimental)
    run
  })
  runs <- Filter(Negate(is.null), runs)
  if (!length(runs)) return(NULL)
  runs <- runs[order(vapply(runs, function(x) as.numeric(x$init), numeric(1)), decreasing = TRUE)]
  stats::setNames(runs, vapply(runs, `[[`, character(1), "id"))
}
