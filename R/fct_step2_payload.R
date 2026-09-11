# Phase 4 shared-context and compact-payload helpers.

step2_weather_store_dir <- function(run_id, root = NULL) {
  root <- root %||% Sys.getenv("WISEAPP_STEP2_WEATHER_STORE_DIR")
  if (!nzchar(root)) root <- file.path(tempdir(), "wiseapp-step2-weather")
  file.path(root, paste0("run-", run_id))
}

step2_weather_store_create <- function(run_id, signature, root = NULL) {
  dir <- step2_weather_store_dir(run_id, root)
  if (!dir.create(dir, recursive = TRUE, showWarnings = FALSE) && !dir.exists(dir)) {
    stop("Could not create Step 2 weather store: ", dir, call. = FALSE)
  }
  manifest <- list(
    schema = 1L,
    run_id = run_id,
    signature = signature,
    created_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
  )
  saveRDS(manifest, file.path(dir, "manifest.rds"))
  list(schema = manifest$schema, run_id = run_id, signature = signature,
       dir = dir, manifest = file.path(dir, "manifest.rds"))
}

step2_weather_store_put <- function(store, key, weather_raw) {
  stopifnot(is.list(store), is.character(key), length(key) == 1L,
            is.data.frame(weather_raw))
  file_key <- digest::digest(key, algo = "sha256")
  path <- file.path(store$dir, paste0(file_key, ".rds"))
  tmp <- paste0(path, ".tmp")
  saveRDS(weather_raw, tmp)
  if (!file.rename(tmp, path)) {
    unlink(tmp)
    stop("Could not publish Step 2 weather reference: ", key, call. = FALSE)
  }
  list(schema = store$schema, run_id = store$run_id, key = key,
       file = path, signature = store$signature)
}

step2_weather_store_get <- function(reference, expected_signature = NULL) {
  if (is.null(reference) || !is.list(reference) ||
      !identical(reference$schema, 1L) ||
      !file.exists(reference$file)) {
    stop("Step 2 weather reference is missing or invalid.", call. = FALSE)
  }
  if (!is.null(expected_signature) &&
      !identical(reference$signature, expected_signature)) {
    stop("Step 2 weather reference is stale for the current run.", call. = FALSE)
  }
  readRDS(reference$file)
}

step2_weather_store_cleanup <- function(store) {
  dir <- if (is.list(store)) store$dir else as.character(store)[1L]
  if (length(dir) && nzchar(dir) && dir.exists(dir)) unlink(dir, recursive = TRUE)
  invisible(NULL)
}

step2_weather_reference <- function(value, expected_signature = NULL) {
  if (is.list(value) && !is.data.frame(value) &&
      identical(value$schema, 1L) && !is.null(value$file)) {
    return(step2_weather_store_get(value, expected_signature))
  }
  value
}

step2_resolve_weather <- function(value, owner = NULL) {
  signature <- owner$weather_signature %||% owner$signature %||% NULL
  step2_weather_reference(value, signature)
}

step2_shared_context <- function(train_aug = NULL,
                                  id_col = NULL,
                                  residuals = NULL,
                                  chol_obj = NULL,
                                  so = NULL,
                                  train_data = NULL,
                                  model_metadata = list()) {
  list(
    schema = 1L,
    train_aug = train_aug,
    id_col = id_col,
    residuals = residuals,
    # chol_obj, so, and train_data already live at result/scenario scope;
    # retaining them here would duplicate serialization without helping compact
    # aggregation consumers.
    model_metadata = model_metadata
  )
}

step2_pipeline_context <- function(pipe, shared_context = NULL) {
  shared_context <- shared_context %||% list()
  list(
    train_aug = pipe$train_aug %||% shared_context$train_aug,
    id_col = pipe$id_col %||% shared_context$id_col,
    residuals = pipe$residuals %||% shared_context$residuals
  )
}

.compact_residual_context <- function(train_aug, id_col, residuals,
                                      compact = TRUE) {
  if (!isTRUE(compact)) return(train_aug)
  if (is.null(train_aug) || identical(residuals, "none")) return(NULL)
  if (!".resid" %in% names(train_aug)) return(train_aug)
  keep <- ".resid"
  if (identical(residuals, "original") && !is.null(id_col) &&
      id_col %in% names(train_aug)) {
    keep <- c(id_col, keep)
  }
  train_aug[, keep, drop = FALSE]
}

.compact_pipeline <- function(pipe) {
  if (is.null(pipe) || !is.list(pipe)) return(pipe)
  pipe$train_aug <- NULL
  pipe$id_col <- NULL
  pipe
}

compact_step2_result <- function(result,
                                 train_aug,
                                 id_col,
                                 residuals,
                                 chol_obj,
                                 so,
                                 train_data,
                                 model_metadata = list()) {
  context <- step2_shared_context(
    train_aug = train_aug,
    id_col = id_col,
    residuals = residuals,
    chol_obj = chol_obj,
    so = so,
    train_data = train_data,
    model_metadata = model_metadata
  )
  if (!is.null(result$hist_sim_result)) {
    result$hist_sim_result$shared_context <- context
    result$hist_sim_result$pipeline <- .compact_pipeline(
      result$hist_sim_result$pipeline
    )
    result$hist_sim_result$train_data <- NULL
    result$hist_sim_result$cluster_counts <- NULL
  }
  result$new_scenarios <- lapply(result$new_scenarios %||% list(), function(s) {
    s$shared_context <- context
    s$pipelines <- lapply(s$pipelines %||% list(), .compact_pipeline)
    s
  })
  result$payload_mode <- "compact"
  result
}

.results_defensive_copy <- function(value) {
  if (is.null(value)) return(NULL)
  unserialize(serialize(value, connection = NULL, version = 3L))
}

.results_frame_matrix <- function(frame, key) {
  .results_defensive_copy(frame$.matrices[[key]])
}

.results_frame_entry <- function(frame, label) {
  .results_defensive_copy(frame$.entries[[label]])
}
