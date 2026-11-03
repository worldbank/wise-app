# Local experimental forecast catalogue (draft-2 schema) ----

.FORECAST_CATALOGUE_FIELDS <- c(
  "id", "product", "lead_unit", "label", "model", "init", "released", "next_release",
  "n_members", "n_leads", "observed_through", "context_months", "context_source", "variables",
  "adjustment", "file", "data_sha256", "manifest_sha256", "status", "data_version"
)
.FORECAST_ADJUSTMENTS <- c("additive_mean_bias_only", "mean_variance_scaled", "ratio")
.FORECAST_STATUSES <- c("draft", "validated", "published")

#' Validated runs of one country's local forecast catalogue
#'
#' A run is validated once here (catalogue row, manifest, checksum of the run file); callers pass the
#' returned run object on instead of verifying again. An invalid run is skipped and listed in
#' `attr(, "skipped")` (data frame with `id` and `reason`), so one bad row does not hide the others.
#' The pipeline guarantees the grid, keys and values of a run file (wise-app-data README), so the
#' app only checks identity.
#' @noRd
.forecast_catalogue_runs <- function(connection_params, code) {
  if (is.null(connection_params) || !identical(connection_params$type %||% "local", "local") ||
      length(code) != 1L || is.na(code) || !grepl("^[A-Z]{3}$", code)) return(NULL)
  root <- connection_params$path %||% .default_data_path()
  .assert_connection_allowed(connection_params)
  catalogue <- file.path(root, "hazard/weather/forecasts", code, "catalogue.csv")
  if (!file.exists(catalogue)) return(NULL)
  entries <- utils::read.csv(catalogue, colClasses = "character", stringsAsFactors = FALSE)
  if (!all(.FORECAST_CATALOGUE_FIELDS %in% names(entries)) || anyDuplicated(entries$id) ||
      anyNA(entries[.FORECAST_CATALOGUE_FIELDS]) ||
      any(!nzchar(unlist(entries[setdiff(.FORECAST_CATALOGUE_FIELDS, "variables")])))) {
    stop("Invalid seasonal forecast catalogue.", call. = FALSE)
  }
  skipped <- list()
  runs <- lapply(seq_len(nrow(entries)), function(i) {
    entry <- as.list(entries[i, .FORECAST_CATALOGUE_FIELDS])
    if (identical(entry$status, "draft") && .on_posit_connect()) return(NULL)
    if (!identical(entry$product, "seasonal") || !identical(entry$lead_unit, "month") ||
        !entry$status %in% .FORECAST_STATUSES) return(NULL)
    tryCatch(.forecast_catalogue_run(entry, root, code), error = function(e) {
      skipped[[length(skipped) + 1L]] <<- data.frame(id = entry$id, reason = conditionMessage(e))
      NULL
    })
  })
  runs <- Filter(Negate(is.null), runs)
  skipped <- if (length(skipped)) do.call(rbind, skipped) else data.frame(id = character(), reason = character())
  if (!length(runs)) {
    if (nrow(skipped)) stop("No valid seasonal forecast run: ", skipped$reason[[1L]], call. = FALSE)
    return(NULL)
  }
  runs <- runs[order(vapply(runs, function(x) as.numeric(x$init), numeric(1)), decreasing = TRUE)]
  structure(stats::setNames(runs, vapply(runs, `[[`, character(1), "id")), skipped = skipped)
}

# One catalogue row to a validated run; stops with a user-readable reason when invalid.
.forecast_catalogue_run <- function(run, root, code) {
  expected <- paste0("hazard/weather/forecasts/", code, "/")
  if (!startsWith(run$file, expected) || grepl("\\\\|(^|/)\\.\\.?(/|$)", run$file) ||
      !grepl("^[A-Za-z0-9_/-]+\\.parquet$", run$file)) {
    stop("Invalid seasonal forecast data path.", call. = FALSE)
  }
  data_path <- file.path(root, run$file)
  manifest_path <- sub("\\.parquet$", ".json", data_path)
  # A manifest is written last by the publisher, so incomplete runs are not offered.
  if (!file.exists(data_path) || !file.exists(manifest_path)) stop("Run file or manifest is missing.", call. = FALSE)
  normalized_root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  if (!.path_under(normalizePath(data_path, winslash = "/", mustWork = TRUE), normalized_root) ||
      !.path_under(normalizePath(manifest_path, winslash = "/", mustWork = TRUE), normalized_root)) {
    stop("Seasonal forecast files must remain within the local data root.", call. = FALSE)
  }
  manifest <- jsonlite::fromJSON(manifest_path, simplifyVector = TRUE)
  if (!identical(manifest$schema_version, "draft-2")) {
    stop("Seasonal forecast manifest is not schema draft-2.", call. = FALSE)
  }
  # One adjustment per variable: `adjustments` (named by variable) when present, else the single `adjustment`.
  manifest_adjustments <- if (length(manifest$adjustments)) {
    unlist(manifest$adjustments)[as.character(manifest$variables)]
  } else {
    rep(as.character(manifest$adjustment), length(manifest$variables))
  }
  if (!length(manifest_adjustments) || anyNA(manifest_adjustments) ||
      !all(manifest_adjustments %in% .FORECAST_ADJUSTMENTS)) {
    stop("Seasonal forecast must declare a supported adjustment.", call. = FALSE)
  }
  for (field in c("init", "released", "next_release", "observed_through")) {
    run[[field]] <- as.Date(run[[field]], format = "%Y-%m-%d")
    if (is.na(run[[field]])) stop("Invalid seasonal forecast date.", call. = FALSE)
  }
  for (field in c("n_members", "n_leads", "context_months")) {
    run[[field]] <- suppressWarnings(as.integer(run[[field]]))
  }
  member_bounds <- as.integer(c(manifest$members$first, manifest$members$last))
  if (length(member_bounds) != 2L || anyNA(member_bounds) || member_bounds[1L] < 0L ||
      member_bounds[2L] < member_bounds[1L] || member_bounds[2L] - member_bounds[1L] > 10000L) {
    stop("Invalid seasonal forecast member range.", call. = FALSE)
  }
  members <- seq.int(member_bounds[1L], member_bounds[2L])
  run$variables <- strsplit(run$variables, ";", fixed = TRUE)[[1L]]
  # The manifest carries `context_months` as a count or as list(n, first, last, sources).
  manifest_context_n <- if (is.list(manifest$context_months)) manifest$context_months$n else manifest$context_months
  if (!identical(manifest$product, run$product) || !identical(manifest$lead_unit, run$lead_unit) ||
      !identical(manifest$initialized_at, format(run$init)) ||
      !identical(manifest$observed_through, format(run$observed_through)) ||
      !identical(manifest$status, run$status) ||
      length(manifest$model) != 1L || !nzchar(manifest$model) ||
      length(manifest$run_id) != 1L || !startsWith(manifest$run_id, paste0(code, "_")) ||
      !length(manifest$variables) || any(!manifest$variables %in% .STEP2_FORECAST_VARS) ||
      anyDuplicated(manifest$variables) || !identical(run$variables, as.character(manifest$variables)) ||
      !identical(run$adjustment, paste(manifest_adjustments, collapse = ";")) ||
      !identical(manifest$h3$type, "int64") || !identical(as.integer(manifest$h3$resolution), 6L) ||
      is.na(run$n_members) || run$n_members < 1L || is.na(run$n_leads) || run$n_leads < 1L ||
      !identical(as.integer(manifest$n_members), run$n_members) || length(members) != run$n_members ||
      !identical(as.integer(manifest$leads), seq_len(run$n_leads)) ||
      !identical(as.character(manifest$valid_months),
        format(seq(run$init, by = "month", length.out = run$n_leads))) ||
      is.na(run$context_months) || run$context_months < 1L ||
      !identical(as.integer(manifest_context_n), run$context_months) ||
      !identical(run$observed_through, .step2_month_add(run$init, -1L))) {
    stop("Seasonal forecast catalogue and manifest disagree.", call. = FALSE)
  }
  checksum <- manifest$output_sha256[[basename(data_path)]]
  if (length(checksum) != 1L || !identical(checksum, run$data_sha256) ||
      !identical(checksum, digest::digest(file = data_path, algo = "sha256"))) {
    stop("Seasonal forecast data checksum does not match its manifest.", call. = FALSE)
  }
  manifest_sha256 <- digest::digest(file = manifest_path, algo = "sha256")
  if (!identical(manifest_sha256, run$manifest_sha256)) {
    stop("Seasonal forecast manifest checksum does not match the catalogue.", call. = FALSE)
  }
  # Optional hindcast skill table, relative to the run's directory; its checksum is part of the identity.
  skill_file <- manifest$skill_file
  if (length(skill_file) == 1L && !is.na(skill_file) && nzchar(skill_file)) {
    if (!grepl("^[A-Za-z0-9_]+/[A-Za-z0-9_.-]+\\.parquet$", skill_file)) {
      stop("Invalid seasonal forecast skill path.", call. = FALSE)
    }
    skill_path <- file.path(dirname(data_path), skill_file)
    skill_sha <- manifest$output_sha256[[skill_file]]
    if (!file.exists(skill_path) || length(skill_sha) != 1L ||
        !identical(skill_sha, digest::digest(file = skill_path, algo = "sha256"))) {
      stop("Seasonal forecast skill file is missing or does not match its manifest.", call. = FALSE)
    }
    run$skill_file <- file.path(dirname(run$file), skill_file)
  } else {
    run$skill_file <- NA_character_
  }
  run$members <- as.integer(members)
  run$model_id <- manifest$model
  run$run_id <- manifest$run_id
  run$experimental <- isTRUE(manifest$experimental)
  run
}
