# Seasonal forecast catalogue (draft-2 schema) ----
#
# Runs are read from the data root of any source. Local files are read from disk; other sources are read
# through load_data() (DuckDB with the source's credentials), like the rest of the app.

.FORECAST_CATALOGUE_FIELDS <- c(
  "id", "product", "lead_unit", "label", "model", "init", "released", "next_release",
  "n_members", "n_leads", "observed_through", "context_months", "context_source", "variables",
  "adjustment", "file", "data_sha256", "manifest_sha256", "status", "data_version"
)
.FORECAST_ADJUSTMENTS <- c("additive_mean_bias_only", "mean_variance_scaled", "ratio")
# Variable names a run file may carry: lower-case column names. A model can use a run only for the variables the
# run lists (`.step2_forecast_unsupported()`), so a newly published variable needs no change here.
.FORECAST_VARIABLE_NAME <- "^[a-z][a-z0-9_]*$"

# A remote read that finds no file: no rows, or a 404 from the source.
.FORECAST_MISSING_PATTERN <- "HTTP 404|No files found|NoSuchKey|does not exist"

# Remote checksums already verified in this process. Only matches are stored, keyed by the source, the file and
# the checksum the catalogue or manifest declares, so a republished file with a new checksum is read again.
.forecast_verified <- new.env(parent = emptyenv())

#' Validated runs of one country's forecast catalogue
#'
#' A run is validated once here (catalogue row, manifest, checksum of the run file); callers pass the
#' returned run object on instead of verifying again. An invalid run is skipped and listed in
#' `attr(, "skipped")` (data frame with `id` and `reason`), so one bad row does not hide the others.
#' The pipeline guarantees the grid, keys and values of a run file (wise-app-data README), so the
#' app only checks identity.
#' @noRd
.forecast_catalogue_runs <- function(connection_params, code) {
  if (is.null(connection_params) || length(code) != 1L || is.na(code) || !grepl("^[A-Z]{3}$", code)) {
    return(NULL)
  }
  .assert_connection_allowed(connection_params)
  text <- .forecast_file_text(connection_params, paste0("hazard/weather/forecasts/", code, "/catalogue.csv"))
  if (is.null(text)) return(NULL)
  entries <- utils::read.csv(text = text, colClasses = "character", stringsAsFactors = FALSE)
  if (!all(.FORECAST_CATALOGUE_FIELDS %in% names(entries)) || anyDuplicated(entries$id) ||
      anyNA(entries[.FORECAST_CATALOGUE_FIELDS]) ||
      any(!nzchar(unlist(entries[setdiff(.FORECAST_CATALOGUE_FIELDS, "variables")])))) {
    stop("Invalid seasonal forecast catalogue.", call. = FALSE)
  }
  skipped <- list()
  runs <- lapply(seq_len(nrow(entries)), function(i) {
    entry <- as.list(entries[i, .FORECAST_CATALOGUE_FIELDS])
    if (!identical(entry$product, "seasonal") || !identical(entry$lead_unit, "month")) return(NULL)
    tryCatch(.forecast_catalogue_run(entry, connection_params, code), error = function(e) {
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
.forecast_catalogue_run <- function(run, connection_params, code) {
  expected <- paste0("hazard/weather/forecasts/", code, "/")
  if (!startsWith(run$file, expected) || grepl("\\\\|(^|/)\\.\\.?(/|$)", run$file) ||
      !grepl("^[A-Za-z0-9_/-]+\\.parquet$", run$file)) {
    stop("Invalid seasonal forecast data path.", call. = FALSE)
  }
  manifest_file <- sub("\\.parquet$", ".json", run$file)
  .forecast_check_local_location(connection_params, c(run$file, manifest_file))
  # A manifest is written last by the publisher, so incomplete runs are not offered.
  manifest_text <- .forecast_file_text(connection_params, manifest_file)
  if (is.null(manifest_text)) stop("Run file or manifest is missing.", call. = FALSE)
  manifest <- jsonlite::fromJSON(manifest_text, simplifyVector = TRUE)
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
      !length(manifest$variables) || !all(grepl(.FORECAST_VARIABLE_NAME, manifest$variables)) ||
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
  checksum <- manifest$output_sha256[[basename(run$file)]]
  if (length(checksum) != 1L || !identical(checksum, run$data_sha256)) {
    stop("Seasonal forecast data checksum does not match its manifest.", call. = FALSE)
  }
  actual <- .forecast_file_sha256(connection_params, run$file, checksum)
  if (is.null(actual)) stop("Run file or manifest is missing.", call. = FALSE)
  if (!identical(actual, checksum)) {
    stop("Seasonal forecast data checksum does not match its manifest.", call. = FALSE)
  }
  manifest_sha256 <- .forecast_file_sha256(connection_params, manifest_file, run$manifest_sha256)
  if (!identical(manifest_sha256, run$manifest_sha256)) {
    stop("Seasonal forecast manifest checksum does not match the catalogue.", call. = FALSE)
  }
  # Optional hindcast skill table, relative to the run's directory; its checksum is part of the identity.
  skill_file <- manifest$skill_file
  if (length(skill_file) == 1L && !is.na(skill_file) && nzchar(skill_file)) {
    if (!grepl("^[A-Za-z0-9_]+/[A-Za-z0-9_.-]+\\.parquet$", skill_file)) {
      stop("Invalid seasonal forecast skill path.", call. = FALSE)
    }
    skill_rel <- file.path(dirname(run$file), skill_file)
    skill_sha <- manifest$output_sha256[[skill_file]]
    if (length(skill_sha) != 1L ||
        !identical(.forecast_file_sha256(connection_params, skill_rel, skill_sha), skill_sha)) {
      stop("Seasonal forecast skill file is missing or does not match its manifest.", call. = FALSE)
    }
    run$skill_file <- skill_rel
  } else {
    run$skill_file <- NA_character_
  }
  run$members <- as.integer(members)
  run$model_id <- manifest$model
  run$run_id <- manifest$run_id
  run$experimental <- isTRUE(manifest$experimental)
  run
}

# Forecast files: local and remote ----

.forecast_is_local <- function(connection_params) identical(connection_params$type %||% "local", "local")

.forecast_local_path <- function(connection_params, rel) {
  file.path(connection_params$path %||% .default_data_path(), rel)
}

# Local files must stay within the data root once symlinks are resolved. Remote paths are checked as strings
# by the caller.
.forecast_check_local_location <- function(connection_params, rels) {
  if (!.forecast_is_local(connection_params)) return(invisible(TRUE))
  root <- normalizePath(connection_params$path %||% .default_data_path(), winslash = "/", mustWork = TRUE)
  for (rel in rels) {
    path <- .forecast_local_path(connection_params, rel)
    if (!file.exists(path)) next
    if (!.path_under(normalizePath(path, winslash = "/", mustWork = TRUE), root)) {
      stop("Seasonal forecast files must remain within the local data root.", call. = FALSE)
    }
  }
  invisible(TRUE)
}

# Text of a forecast file under the data root; NULL when it does not exist.
.forecast_file_text <- function(connection_params, rel) {
  if (.forecast_is_local(connection_params)) {
    path <- .forecast_local_path(connection_params, rel)
    if (!file.exists(path)) return(NULL)
    return(paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n"))
  }
  .forecast_remote_text(connection_params, rel)
}

# SHA-256 of a forecast file under the data root; NULL when it does not exist. A remote file is hashed once per
# process when its checksum matches `expected`, so the reactive catalogue read does not download run files again.
.forecast_file_sha256 <- function(connection_params, rel, expected) {
  if (.forecast_is_local(connection_params)) {
    path <- .forecast_local_path(connection_params, rel)
    if (!file.exists(path)) return(NULL)
    return(digest::digest(file = path, algo = "sha256"))
  }
  key <- digest::digest(list(connection_params, rel, expected))
  if (isTRUE(.forecast_verified[[key]])) return(expected)
  sha <- .forecast_remote_sha256(connection_params, rel)
  if (!is.null(sha) && identical(sha, expected)) assign(key, TRUE, envir = .forecast_verified)
  sha
}

.forecast_remote_text <- function(connection_params, rel) {
  out <- .forecast_remote_collect(connection_params, rel, "text", function(tbl) dplyr::collect(tbl))
  if (is.null(out) || !nrow(out)) return(NULL)
  paste(out$content, collapse = "\n")
}

.forecast_remote_sha256 <- function(connection_params, rel) {
  out <- .forecast_remote_collect(connection_params, rel, "blob", function(tbl) {
    dplyr::collect(dplyr::transmute(tbl, sha = dbplyr::sql("sha256(content)")))
  })
  if (is.null(out) || !nrow(out)) return(NULL)
  out$sha[[1L]]
}

# Collects a remote forecast file through load_data(). NULL when the file is absent; other errors, such as
# credentials or network failures, are raised so they show in the UI.
.forecast_remote_collect <- function(connection_params, rel, format, query) {
  tryCatch(
    query(load_data(rel, connection_params, format = format)),
    error = function(e) {
      if (grepl(.FORECAST_MISSING_PATTERN, conditionMessage(e))) return(NULL)
      stop(e)
    }
  )
}
