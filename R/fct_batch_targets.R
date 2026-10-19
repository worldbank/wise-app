# Batch runner ----
# A `targets` pipeline over a run grid. One dynamic branch per unique stage id
# (`data_id`, then `wxvar_id`), not per leaf run, so runs that share a sample
# or a weather variable share the work. Branch functions never signal an
# error: a failure becomes a record in the `failures` table and downstream
# branches of the same data are skipped. Results are written as parquet
# datasets (one per table, partitioned by `code`) plus the run catalogue.
# `targets`, `crew`, `yaml` and `arrow` are suggested packages.

# Schema version of the published tables (manifest.json).
WISEAPP_BATCH_SCHEMA_VERSION <- 1L

# Pipeline definition ----

#' Targets for a batch run
#'
#' Returns the list of targets to put in `_targets.R`: the grid, one branch
#' per unique data set and weather variable, and the writer of the results
#' store. Needs the `targets` package; the data location and credentials come
#' from the environment variables of the app (`WISEAPP_DATA_PATH` for local
#' data).
#'
#' @param spec_file Path to the grid YAML file (relative to the project).
#' @param out_dir Results folder.
#'
#' @return A list of targets.
#' @export
wise_targets <- function(spec_file, out_dir = "results") {
  .need_pkg("targets", "run a batch pipeline")
  t <- targets::tar_target_raw
  list(
    t("spec_file", bquote(.(spec_file)), format = "file", deps = character(0)),
    # Always re-read the metadata digest: changed survey metadata reruns the
    # data branches, an unchanged grid keeps every branch.
    t("grid", quote(wiseapp::wise_batch_grid(spec_file)), cue = targets::tar_cue(mode = "always")),
    t("data_specs", quote(wiseapp::wise_batch_unique(grid, "data")), iteration = "list"),
    t("data_frames", quote(wiseapp::wise_batch_data(data_specs)),
      pattern = quote(map(data_specs)), format = "file"
    ),
    t("data_tables", quote(wiseapp::wise_batch_data_tables(data_specs, data_frames)),
      pattern = quote(map(data_specs, data_frames)), iteration = "list"
    ),
    t("wx_specs", quote(wiseapp::wise_batch_unique(grid, "weather", data_specs, data_frames)),
      iteration = "list"
    ),
    t("weather_tables", quote(wiseapp::wise_batch_weather(wx_specs)),
      pattern = quote(map(wx_specs)), iteration = "list"
    ),
    # Step 1 models: the merged survey-weather frame once per weather
    # profile, then one fit per model specification.
    t("wx_frame_specs", quote(wiseapp::wise_batch_unique(grid, "frame", data_specs, data_frames)),
      iteration = "list"
    ),
    t("wx_frames", quote(wiseapp::wise_batch_frame(wx_frame_specs)),
      pattern = quote(map(wx_frame_specs)), format = "file"
    ),
    t("fit_specs", quote(wiseapp::wise_batch_unique(
      grid, "fit", data_specs, data_frames, wx_frame_specs, wx_frames
    )), iteration = "list"),
    t("fit_tables", quote(wiseapp::wise_batch_fit(fit_specs)),
      pattern = quote(map(fit_specs)), iteration = "list"
    ),
    t("results", bquote(wiseapp::wise_batch_write(
      .(out_dir), grid, data_tables, weather_tables, fit_tables
    )),
      format = "file"
    )
  )
}

#' Controller for a batch run on one machine
#'
#' A `crew` local controller whose workers share the machine: the DuckDB and
#' compute thread limits of the app are set from the core count and, when
#' given, the memory, divided by the number of workers.
#'
#' @param workers Number of parallel workers.
#' @param cores Cores to share (default: all).
#' @param memory_gb Memory to share in GB (`NULL` leaves DuckDB's default).
#'
#' @return A `crew` controller for `targets::tar_option_set(controller = )`.
#' @export
wise_batch_controller <- function(workers = 1L, cores = parallel::detectCores(), memory_gb = NULL) {
  .need_pkg("crew", "run branches in parallel")
  per_worker <- max(1L, floor(cores / workers))
  Sys.setenv(
    WISEAPP_DUCKDB_THREADS = per_worker,
    WISEAPP_THREADS = per_worker
  )
  if (!is.null(memory_gb)) {
    Sys.setenv(WISEAPP_DUCKDB_MEMORY_LIMIT = sprintf("%dGB", max(1L, floor(memory_gb / workers))))
  }
  crew::crew_controller_local(workers = workers)
}

#' Copy the batch project template
#'
#' Copies `_targets.R`, `spec.yaml`, `run.R` and a README into a new folder.
#'
#' @param path Folder to create.
#' @return `path`, invisibly.
#' @export
wise_batch_template <- function(path) {
  src <- system.file("batch", package = "wiseapp")
  if (!nzchar(src)) stop("The batch template is not installed with this package.", call. = FALSE)
  if (file.exists(path) && length(list.files(path, all.files = TRUE, no.. = TRUE))) {
    stop("'", path, "' exists and is not empty.", call. = FALSE)
  }
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  file.copy(list.files(src, full.names = TRUE, all.files = TRUE, no.. = TRUE), path, recursive = TRUE)
  invisible(path)
}


# Branch functions ----

# A failed stage: classified message, logged in full by wise_user_error().
#' @noRd
.batch_failure <- function(stage, id, e) {
  list(
    ok = FALSE, stage = stage, id = id,
    error_class = class(e)[1L],
    message = wise_user_error(e, paste("batch", stage))
  )
}

#' @noRd
.batch_dir <- function(...) {
  dir <- file.path(targets::tar_path_store(), "user", ...)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  dir
}

#' Resolve the run grid
#'
#' @param spec_file Path to the grid YAML file.
#' @param connection_params Connection (default: the environment's).
#' @return A list: `runs` (the expanded, resolved grid), `source`
#'   (connection label and metadata digest).
#' @keywords internal
#' @export
wise_batch_grid <- function(spec_file, connection_params = NULL) {
  .need_pkg("yaml", "read a grid file")
  grid <- yaml::read_yaml(spec_file)
  source_type <- grid$source$type %||% "local"
  cp <- connection_params %||% wise_batch_connection(list(type = source_type))
  if (identical(cp$type, "local") && !nzchar(cp$path %||% "")) {
    stop("Set WISEAPP_DATA_PATH to the data folder before running a batch.", call. = FALSE)
  }
  md <- load_overview_metadata(cp)
  runs <- wise_spec_expand(spec_file, connection_params = cp, metadata = md)
  list(
    runs = runs,
    source = c(
      .provenance_source_label(cp),
      list(metadata_digest = digest::digest(md[c("survey_list", "variable_list", "cpi_ppp")], algo = "sha256"))
    ),
    started = Sys.time()
  )
}

#' One work item per unique stage id
#'
#' @param grid Result of `wise_batch_grid()`.
#' @param stage `"data"`, `"weather"` (one variable's statistics), `"frame"`
#'   (the survey-weather frame of a weather profile; runs with a model only) or
#'   `"fit"` (one model fit).
#' @param data_specs,data_frames For `"weather"`, `"frame"` and `"fit"`: the
#'   data items and the files their branches wrote, to attach the file of each
#'   item's data.
#' @param frame_specs,frames For `"fit"`: the frame items and their files.
#' @return A list of items (`id`, `spec`, ...). Items hold only the spec
#'   sections their stage depends on, so adding a model profile leaves the
#'   items of the earlier stages unchanged.
#' @keywords internal
#' @export
wise_batch_unique <- function(grid, stage = c("data", "weather", "frame", "fit"), data_specs = NULL,
                              data_frames = NULL, frame_specs = NULL, frames = NULL) {
  stage <- match.arg(stage)
  runs <- grid$runs
  no_model <- function(spec) {
    spec$model <- NULL
    spec
  }
  data_file <- function(data_id) {
    data_frames[match(data_id, vapply(data_specs, `[[`, "", "id"))]
  }
  if (identical(stage, "data")) {
    first <- !duplicated(runs$data_id)
    digest <- grid$source$metadata_digest
    return(unname(Map(
      function(id, spec) list(id = id, spec = no_model(spec), metadata_digest = digest),
      runs$data_id[first], runs$spec[first]
    )))
  }
  # A grid without models still needs one (inert) item: a target cannot
  # branch over an empty one.
  none <- list(list(id = "none", none = TRUE))
  if (identical(stage, "frame")) {
    keep <- !is.na(runs$fit_id) & !duplicated(runs$weather_id)
    items <- unname(Map(
      function(id, data_id, spec) {
        list(id = id, data_id = data_id, spec = no_model(spec), data_file = data_file(data_id))
      },
      runs$weather_id[keep], runs$data_id[keep], runs$spec[keep]
    ))
    return(if (length(items)) items else none)
  }
  if (identical(stage, "fit")) {
    keep <- !is.na(runs$fit_id) & !duplicated(runs$fit_id)
    items <- unname(Map(
      function(id, weather_id, data_id, spec) {
        list(
          id = id, weather_id = weather_id, data_id = data_id, spec = spec,
          data_file = data_file(data_id),
          frame_file = frames[match(weather_id, vapply(frame_specs, `[[`, "", "id"))]
        )
      },
      runs$fit_id[keep], runs$weather_id[keep], runs$data_id[keep], runs$spec[keep]
    ))
    return(if (length(items)) items else none)
  }
  items <- list()
  for (i in seq_len(nrow(runs))) {
    for (v in names(runs$wxvar_ids[[i]])) {
      id <- runs$wxvar_ids[[i]][[v]]
      if (is.null(items[[id]])) {
        items[[id]] <- list(
          id = id, variable = v, data_id = runs$data_id[i], spec = no_model(runs$spec[[i]]),
          data_file = data_file(runs$data_id[i])
        )
      }
    }
  }
  unname(items)
}

#' Prepare the survey data of one data set
#'
#' Selects the surveys, loads and prepares them, and adds the outcome. The
#' result goes to a file in the targets store for the weather branches and
#' the table branch to read.
#'
#' @param item A data item from `wise_batch_unique()`.
#' @param connection_params Connection (default: the environment's).
#' @return The path of the file holding the prepared data (or the failure).
#' @keywords internal
#' @export
wise_batch_data <- function(item, connection_params = NULL) {
  path <- file.path(.batch_dir("data"), paste0(item$id, ".qs2"))
  res <- tryCatch(
    {
      t0 <- Sys.time()
      spec <- item$spec
      cp <- connection_params %||% wise_batch_connection(spec$source)
      md <- load_overview_metadata(cp)
      ss <- wise_select_surveys(
        md$survey_list, spec$sample$unit, cp, spec$sample$countries, spec$sample$years
      )
      df <- prepare_survey_data(load_survey_frame(ss, cp), md$variable_list, md$cpi_ppp)
      # Location panel for clustered inference (the Survey stats tab does the
      # same). Without it the models use fixest's default variance, and the
      # model tables say so.
      panel <- tryCatch(wise_load_location_panel(ss, cp), error = function(e) e)
      if (inherits(panel, "error")) {
        location_panel <- list(ok = FALSE, message = wise_user_error(panel, "batch location panel"))
      } else {
        df <- wise_join_location_panel(df, panel)
        location_panel <- list(ok = TRUE, message = NA_character_, n_unmatched = sum(is.na(df$loc_id_panel)))
      }
      oc <- wise_selected_outcome(
        md$variable_list, df, spec$outcome$name, spec$outcome$currency, spec$outcome$poverty_line
      )
      list(
        ok = TRUE, id = item$id, survey_data = df,
        outcome_data = wise_outcome_data(df, oc$info, oc$so), outcome = oc,
        selected_surveys = ss, variable_list = md$variable_list, location_panel = location_panel,
        seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")),
        source = c(.provenance_source_label(cp), list(
          files = paste0(ss$fname, ":", file.size(ss$fpath), collapse = ";")
        ))
      )
    },
    error = function(e) .batch_failure("data", item$id, e)
  )
  qs2::qs_save(res, path)
  path
}

#' Build the survey tables of one data set
#'
#' @param item A data item.
#' @param file Path returned by `wise_batch_data()` for the same item.
#' @return A list: `ok`, `id`, `tables` (`variable_stats`, `interview_dates`),
#'   `provenance` (one row).
#' @keywords internal
#' @export
wise_batch_data_tables <- function(item, file) {
  d <- qs2::qs_read(file)
  if (!isTRUE(d$ok)) {
    return(d)
  }
  tryCatch(
    {
      spec <- item$spec
      t0 <- Sys.time()
      vs <- variable_stats_table(
        d$outcome_data, d$variable_list, d$outcome$info$name[1],
        spec$stats$indicators, spec$stats$location_samples
      )
      idt <- interview_dates_table(d$outcome_data)
      add_id <- function(x) if (is.null(x)) NULL else cbind(data_id = item$id, x)
      list(
        ok = TRUE, id = item$id,
        tables = list(variable_stats = add_id(vs), interview_dates = add_id(idt)),
        provenance = data.frame(
          stage = "data", id = item$id, n_rows = nrow(d$survey_data),
          n_surveys = nrow(d$selected_surveys),
          source_type = d$source$type, source_origin = d$source$origin,
          source_files = d$source$files,
          location_panel = if (isTRUE(d$location_panel$ok)) "joined" else d$location_panel$message,
          n_no_panel = d$location_panel$n_unmatched %||% NA_integer_,
          seconds = d$seconds + as.numeric(difftime(Sys.time(), t0, units = "secs")),
          stringsAsFactors = FALSE
        )
      )
    },
    error = function(e) .batch_failure("data", item$id, e)
  )
}

#' Build the weather statistics of one weather variable
#'
#' Loads the weather as continuous values (the descriptive tables use the
#' values before binning), merges it onto the survey data of the item and
#' summarises the sample and the historical comparison.
#'
#' @param item A weather item from `wise_batch_unique()`.
#' @param connection_params Connection (default: the environment's).
#' @return A list: `ok`, `id`, `tables` (`weather_stats`), `provenance`.
#' @keywords internal
#' @export
wise_batch_weather <- function(item, connection_params = NULL) {
  d <- qs2::qs_read(item$data_file)
  if (!isTRUE(d$ok)) {
    return(list(ok = FALSE, stage = "weather", id = item$id, skipped = TRUE, message = "The data stage failed."))
  }
  tryCatch(
    {
      t0 <- Sys.time()
      spec <- item$spec
      v <- item$variable
      cp <- connection_params %||% wise_batch_connection(spec$source)
      hy <- stats::setNames(spec$weather$hist_years, c("from", "to"))
      wx <- stats::setNames(list(spec$weather[[v]]), v)
      wx$hist_years <- spec$weather$hist_years
      wx[[v]]$form <- "Continuous"
      sw <- wise_selected_weather(wx, d$variable_list)
      w <- wise_load_weather(d$survey_data, d$selected_surveys, sw, hy, cp, WISEAPP_DEFAULT_SEED)
      tab <- weather_stats_table(
        w$survey_weather, sw[1, ], d$survey_data, w$hist_cells, hy, spec$stats$location_samples
      )
      list(
        ok = TRUE, id = item$id,
        tables = list(weather_stats = if (is.null(tab)) NULL else cbind(wxvar_id = item$id, tab)),
        provenance = data.frame(
          stage = "weather", id = item$id, n_rows = nrow(w$survey_weather),
          n_surveys = nrow(d$selected_surveys),
          source_type = d$source$type, source_origin = d$source$origin,
          source_files = d$source$files,
          seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")),
          stringsAsFactors = FALSE
        )
      )
    },
    error = function(e) .batch_failure("weather", item$id, e)
  )
}


#' Build the survey-weather frame of one weather profile
#'
#' Loads the weather as the profile specifies it (binned variables cut on the
#' sample's breaks, seeded for K-means), merges it onto the survey data of the
#' item and stores the frame in the targets store for the fit branches.
#'
#' @param item A frame item from `wise_batch_unique()`.
#' @param connection_params Connection (default: the environment's).
#' @return The path of the file holding the frame (or the failure).
#' @keywords internal
#' @export
wise_batch_frame <- function(item, connection_params = NULL) {
  path <- file.path(.batch_dir("frames"), paste0(item$id, ".qs2"))
  res <- tryCatch(
    {
      d <- if (isTRUE(item$none)) list(ok = FALSE) else qs2::qs_read(item$data_file)
      if (!isTRUE(d$ok)) {
        list(ok = FALSE, stage = "frame", id = item$id, skipped = TRUE, message = "The data stage failed.")
      } else {
        t0 <- Sys.time()
        spec <- item$spec
        cp <- connection_params %||% wise_batch_connection(spec$source)
        hy <- stats::setNames(spec$weather$hist_years, c("from", "to"))
        sw <- wise_selected_weather(spec$weather, d$variable_list)
        w <- wise_load_weather(d$survey_data, d$selected_surveys, sw, hy, cp, spec$seed)
        list(
          ok = TRUE, id = item$id, survey_weather = w$survey_weather,
          stored_breaks = w$stored_breaks, selected_weather = sw,
          seconds = as.numeric(difftime(Sys.time(), t0, units = "secs"))
        )
      }
    },
    error = function(e) .batch_failure("frame", item$id, e)
  )
  qs2::qs_save(res, path)
  path
}

#' Fit the Step 1 models of one specification and build the model tables
#'
#' The batch counterpart of pressing "Run model": covariates (user list or
#' Lasso), fixed effects and the three progressive fits, then the tables
#' `model_terms`, `model_fit` and `model_vcov`. The fit itself is not kept.
#'
#' @param item A fit item from `wise_batch_unique()`.
#' @return A list: `ok`, `id`, `tables`, `provenance` (one row); or a failure
#'   record.
#' @keywords internal
#' @export
wise_batch_fit <- function(item) {
  if (isTRUE(item$none)) {
    return(list(ok = FALSE, stage = "fit", id = item$id, skipped = TRUE, message = "No model in the grid."))
  }
  d <- qs2::qs_read(item$data_file)
  if (!isTRUE(d$ok)) {
    return(list(ok = FALSE, stage = "fit", id = item$id, skipped = TRUE, message = "The data stage failed."))
  }
  w <- qs2::qs_read(item$frame_file)
  if (!isTRUE(w$ok)) {
    return(if (isTRUE(w$skipped)) {
      list(ok = FALSE, stage = "fit", id = item$id, skipped = TRUE, message = w$message)
    } else {
      w
    })
  }
  tryCatch(
    {
      t0 <- Sys.time()
      spec <- item$spec
      so <- d$outcome$so
      m <- wise_model_from_spec(
        spec$model, spec$sample$unit, w$survey_weather, so, w$selected_weather,
        d$variable_list, spec$seed
      )
      mf <- wise_fit(
        w$survey_weather, w$stored_breaks, so, w$selected_weather, m$selected_model,
        d$variable_list, spec$seed
      )
      tables <- step1_model_tables(mf, m$selection_frequency)
      # Inference level: say when the location panel was not available.
      panel <- if (isTRUE(d$location_panel$ok)) "joined" else paste0("unavailable: ", d$location_panel$message)
      tables$model_fit <- rbind(tables$model_fit, data.frame(
        section = "spec", variable = NA_character_, model = NA_integer_, tau = NA_real_,
        statistic = "location_panel", value = NA_real_, text = panel, detail = NA_character_,
        stringsAsFactors = FALSE
      ))
      code <- paste(spec$sample$countries, collapse = "+")
      add_id <- function(x) if (is.null(x)) NULL else cbind(fit_id = item$id, code = code, x)
      list(
        ok = TRUE, id = item$id,
        tables = lapply(tables, add_id),
        provenance = data.frame(
          stage = "fit", id = item$id, n_rows = nrow(mf$train_data),
          n_surveys = nrow(d$selected_surveys),
          source_type = d$source$type, source_origin = d$source$origin,
          source_files = d$source$files, location_panel = panel,
          seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")),
          stringsAsFactors = FALSE
        )
      )
    },
    error = function(e) .batch_failure("fit", item$id, e)
  )
}


# Results store ----

# One row of flattened settings per run.
#' @noRd
.spec_flat <- function(spec) {
  data.frame(
    seed = spec$seed, unit = spec$sample$unit,
    countries = paste(spec$sample$countries, collapse = "+"),
    years = .spec_json(spec$sample$years),
    outcome = spec$outcome$name %||% NA_character_, currency = spec$outcome$currency,
    poverty_line = spec$outcome$poverty_line %||% NA_real_,
    weather_vars = paste(wise_spec_weather_vars(spec$weather), collapse = ","),
    weather = .spec_json(spec$weather[wise_spec_weather_vars(spec$weather)]),
    hist_from = spec$weather$hist_years[1], hist_to = spec$weather$hist_years[2],
    location_samples = spec$stats$location_samples,
    model_type = spec$model$type %||% NA_character_,
    fixed_effects = if (is.null(spec$model) || is.null(spec$model$fixed_effects)) {
      NA_character_
    } else {
      paste(spec$model$fixed_effects, collapse = ",")
    },
    covariate_method = spec$model$covariates$method %||% NA_character_,
    covariates = if (is.null(spec$model)) NA_character_ else .spec_json(spec$model$covariates),
    stringsAsFactors = FALSE
  )
}

# Write one table as a parquet dataset partitioned by country code, replacing
# what an earlier run left.
#' @noRd
.write_table <- function(tab, out_dir, name) {
  dir <- file.path(out_dir, "tables", name)
  unlink(dir, recursive = TRUE)
  if (is.null(tab) || !nrow(tab)) {
    return(invisible(NULL))
  }
  arrow::write_dataset(tab, dir, format = "parquet", partitioning = "code")
  invisible(dir)
}

#' @noRd
.git_sha <- function() {
  pkg <- tryCatch(utils::packageDescription("wiseapp"), error = function(e) NULL)
  sha <- pkg$RemoteSha %||% pkg$GithubSHA1
  if (!is.null(sha)) {
    return(sha)
  }
  path <- tryCatch(getNamespaceInfo(asNamespace("wiseapp"), "path"), error = function(e) NULL)
  if (is.null(path) || !dir.exists(file.path(path, ".git"))) {
    return(NA_character_)
  }
  out <- tryCatch(
    suppressWarnings(system2("git", c("-C", shQuote(path), "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE)),
    error = function(e) NA_character_
  )
  if (length(out)) out[1L] else NA_character_
}

#' Write the results store
#'
#' @param out_dir Results folder.
#' @param grid Result of `wise_batch_grid()`.
#' @param data_tables,weather_tables,fit_tables Branch results.
#' @return `out_dir` (a `targets` file target).
#' @keywords internal
#' @export
wise_batch_write <- function(out_dir, grid, data_tables, weather_tables, fit_tables = list()) {
  .need_pkg("arrow", "write result tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  runs <- grid$runs
  ok <- function(x) Filter(function(b) isTRUE(b$ok), x)
  pick <- function(branches, name) {
    dplyr::bind_rows(lapply(ok(branches), function(b) b$tables[[name]]))
  }

  .write_table(pick(data_tables, "variable_stats"), out_dir, "variable_stats")
  .write_table(pick(data_tables, "interview_dates"), out_dir, "interview_dates")
  .write_table(pick(weather_tables, "weather_stats"), out_dir, "weather_stats")
  for (name in c("model_terms", "model_fit", "model_vcov")) {
    .write_table(pick(fit_tables, name), out_dir, name)
  }

  # Run catalogue and per-run specs.
  flat <- dplyr::bind_rows(lapply(runs$spec, .spec_flat))
  axes <- setdiff(names(runs), c(
    "run_id", "data_id", "wxvar_ids", "weather_id", "fit_id", "resolved", "spec"
  ))
  labels <- tibble::as_tibble(runs[axes])
  names(labels) <- paste0("axis_", axes)
  catalogue <- dplyr::bind_cols(
    tibble::as_tibble(runs[c("run_id", "data_id")]), labels,
    tibble::tibble(wxvar_ids = lapply(runs$wxvar_ids, unname)),
    tibble::as_tibble(runs[c("weather_id", "fit_id")]),
    flat,
    tibble::tibble(spec_json = vapply(runs$spec, .spec_json, ""))
  )
  arrow::write_parquet(catalogue, file.path(out_dir, "runs.parquet"))
  unlink(file.path(out_dir, "specs"), recursive = TRUE)
  dir.create(file.path(out_dir, "specs"), showWarnings = FALSE)
  for (i in seq_len(nrow(runs))) {
    wise_spec_write(runs$spec[[i]], file.path(out_dir, "specs", paste0(runs$run_id[i], ".json")))
  }

  # Provenance and failures.
  prov <- dplyr::bind_rows(lapply(
    c(ok(data_tables), ok(weather_tables), ok(fit_tables)), function(b) b$provenance
  ))
  prov$wiseapp_version <- as.character(utils::packageVersion("wiseapp"))
  prov$completed_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  arrow::write_parquet(prov, file.path(out_dir, "provenance.parquet"))

  failed <- Filter(
    function(b) is.list(b) && !isTRUE(b$ok) && !isTRUE(b$skipped),
    c(data_tables, weather_tables, fit_tables)
  )
  # Fit branches that share a failed weather frame report it once.
  failed <- failed[!duplicated(vapply(failed, function(b) paste(b$stage, b$id), ""))]
  failures <- dplyr::bind_rows(lapply(failed, function(b) {
    affected <- switch(b$stage,
      data = runs$run_id[runs$data_id == b$id],
      frame = runs$run_id[runs$weather_id == b$id],
      fit = runs$run_id[runs$fit_id %in% b$id],
      runs$run_id[vapply(runs$wxvar_ids, function(x) b$id %in% x, logical(1))]
    )
    data.frame(
      stage = b$stage, id = b$id, run_ids = paste(affected, collapse = ","),
      n_runs = length(affected), error_class = b$error_class, message = b$message,
      stringsAsFactors = FALSE
    )
  }))
  if (!nrow(failures)) {
    failures <- data.frame(
      stage = character(), id = character(), run_ids = character(), n_runs = integer(),
      error_class = character(), message = character(), stringsAsFactors = FALSE
    )
  }
  arrow::write_parquet(failures, file.path(out_dir, "failures.parquet"))

  # Manifest.
  tables <- list.dirs(file.path(out_dir, "tables"), recursive = FALSE, full.names = FALSE)
  renv_lock <- "renv.lock"
  manifest <- list(
    schema_version = WISEAPP_BATCH_SCHEMA_VERSION,
    wiseapp_version = as.character(utils::packageVersion("wiseapp")),
    wiseapp_git_sha = .git_sha(),
    r_version = paste0(R.version$major, ".", R.version$minor),
    duckdb_version = as.character(utils::packageVersion("duckdb")),
    renv_lock_sha256 = if (file.exists(renv_lock)) digest::digest(file = renv_lock, algo = "sha256") else NA_character_,
    data_source = grid$source,
    started_at = format(grid$started, "%Y-%m-%dT%H:%M:%S%z"),
    finished_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    n_runs = nrow(runs), n_data_sets = length(data_tables), n_weather_variables = length(weather_tables),
    n_fits = length(fit_tables), n_failures = nrow(failures), tables = as.list(tables)
  )
  writeLines(
    jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE, na = "null", null = "null"),
    file.path(out_dir, "manifest.json")
  )
  out_dir
}
