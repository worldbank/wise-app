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
#' @param keep_step2 Keep the stored Step 2 run of each simulation that has a
#'   policy (hundreds of MB each, in the targets store) after the policy branches
#'   have run. The default keeps them, so a new policy profile does not repeat
#'   the simulation; `FALSE` deletes them at the end of the run and a later
#'   policy-only change then needs the simulation target invalidated
#'   (`targets::tar_invalidate(sim_tables)`). Runs of simulations that are no
#'   longer in the grid are always deleted.
#'
#' @return A list of targets.
#' @export
wise_targets <- function(spec_file, out_dir = "results", keep_step2 = TRUE) {
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
    # Step 2: one run per sim_id, on the fit and the frame of its runs. The
    # runs are memory-heavy, so they use the `sim` controller when the
    # pipeline defines one (see `wise_batch_controller()`).
    t("sim_specs", quote(wiseapp::wise_batch_unique(
      grid, "sim", data_specs, data_frames, wx_frame_specs, wx_frames, fit_specs, fit_tables
    )), iteration = "list"),
    t("sim_tables", quote(wiseapp::wise_batch_sim(sim_specs)),
      pattern = quote(map(sim_specs)), iteration = "list", resources = .batch_sim_resources()
    ),
    # Step 3: one run per policy_id, on the stored Step 2 run of its sim_id.
    t("policy_specs", quote(wiseapp::wise_batch_unique(
      grid, "policy", data_specs, data_frames, wx_frame_specs, wx_frames, fit_specs, fit_tables,
      sim_specs, sim_tables
    )), iteration = "list"),
    t("policy_tables", quote(wiseapp::wise_batch_policy(policy_specs)),
      pattern = quote(map(policy_specs)), iteration = "list", resources = .batch_sim_resources()
    ),
    t("results", bquote(wiseapp::wise_batch_write(
      .(out_dir), grid, data_tables, weather_tables, fit_tables, sim_tables, policy_tables,
      keep_step2 = .(keep_step2)
    )),
      format = "file"
    )
  )
}

# Resources of the Step 2 branches: the `sim` crew controller, when the
# pipeline has one.
#' @noRd
.batch_sim_resources <- function() {
  ctl <- tryCatch(targets::tar_option_get("controller"), error = function(e) NULL)
  if (is.null(ctl) || !"sim" %in% names(ctl$controllers %||% list())) {
    return(targets::tar_resources())
  }
  targets::tar_resources(crew = targets::tar_resources_crew(controller = "sim"))
}

#' Controller for a batch run on one machine
#'
#' A `crew` local controller whose workers share the machine: the DuckDB and
#' compute thread limits of the app are set from the core count and, when
#' given, the memory, divided by the number of workers. The Step 2 runs hold
#' hundreds of MB each, so with `sim_workers` they get a controller of their
#' own (named `sim`) with fewer workers than the other stages.
#'
#' @param workers Number of parallel workers for the data, weather and fit
#'   stages.
#' @param cores Cores to share (default: all).
#' @param memory_gb Memory to share in GB (`NULL` leaves DuckDB's default).
#' @param sim_workers Workers for the Step 2 runs (`NULL`: the same
#'   controller as the other stages).
#'
#' @return A `crew` controller (a controller group with `sim_workers`) for
#'   `targets::tar_option_set(controller = )`.
#' @export
wise_batch_controller <- function(workers = 1L, cores = parallel::detectCores(), memory_gb = NULL,
                                  sim_workers = NULL) {
  .need_pkg("crew", "run branches in parallel")
  total <- workers + (sim_workers %||% 0L)
  per_worker <- max(1L, floor(cores / total))
  Sys.setenv(
    WISEAPP_DUCKDB_THREADS = per_worker,
    WISEAPP_THREADS = per_worker
  )
  if (!is.null(memory_gb)) {
    Sys.setenv(WISEAPP_DUCKDB_MEMORY_LIMIT = sprintf("%dGB", max(1L, floor(memory_gb / total))))
  }
  if (is.null(sim_workers)) {
    return(crew::crew_controller_local(workers = workers))
  }
  crew::crew_controller_group(
    crew::crew_controller_local(name = "default", workers = workers),
    crew::crew_controller_local(name = "sim", workers = sim_workers)
  )
}

#' Copy the batch project template
#'
#' Copies `_targets.R`, `spec.yaml`, `run.R`, `check_reproducibility.R` and a
#' README into a new folder.
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
#'   (connection label and metadata digest) and `data_files` (file names and
#'   SHA-256 of the survey files of the runs' economies; `NULL` for sources
#'   other than a local folder).
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
  digest_cache <- tryCatch(file.path(.batch_dir(), "data_digest.rds"), error = function(e) NULL)
  list(
    runs = runs,
    source = c(
      .provenance_source_label(cp),
      list(metadata_digest = digest::digest(md[c("survey_list", "variable_list", "cpi_ppp")], algo = "sha256"))
    ),
    data_files = .batch_data_digest(cp$path, runs, cache_file = digest_cache),
    started = Sys.time()
  )
}

#' One work item per unique stage id
#'
#' @param grid Result of `wise_batch_grid()`.
#' @param stage `"data"`, `"weather"` (one variable's statistics), `"frame"`
#'   (the survey-weather frame of a weather profile; runs with a model only),
#'   `"fit"` (one model fit) or `"sim"` (one Step 2 run; runs with a `sim`
#'   section only).
#' @param data_specs,data_frames For `"weather"`, `"frame"`, `"fit"` and
#'   `"sim"`: the data items and the files their branches wrote, to attach the
#'   file of each item's data.
#' @param frame_specs,frames For `"fit"` and `"sim"`: the frame items and their
#'   files.
#' @param fit_specs,fits For `"sim"` and `"policy"`: the fit items and their
#'   branch results (each holds the file of the fit).
#' @param sim_specs,sims For `"policy"`: the simulation items and their branch
#'   results (each holds the file of the stored Step 2 run).
#' @return A list of items (`id`, `spec`, ...). Items hold only the spec
#'   sections their stage depends on, so adding a model or simulation profile
#'   leaves the items of the earlier stages unchanged.
#' @keywords internal
#' @export
wise_batch_unique <- function(grid, stage = c("data", "weather", "frame", "fit", "sim", "policy"),
                              data_specs = NULL, data_frames = NULL, frame_specs = NULL, frames = NULL,
                              fit_specs = NULL, fits = NULL, sim_specs = NULL, sims = NULL) {
  stage <- match.arg(stage)
  runs <- grid$runs
  # The sections of the spec a stage reads: an item holds nothing else, so an
  # edit elsewhere in the spec leaves its branch up to date.
  sections <- function(spec, ...) spec[intersect(c(...), names(spec))]
  data_file <- function(data_id) {
    data_frames[match(data_id, vapply(data_specs, `[[`, "", "id"))]
  }
  if (identical(stage, "data")) {
    first <- !duplicated(runs$data_id)
    digest <- grid$source$metadata_digest
    return(unname(Map(
      function(id, spec) {
        list(
          id = id, spec = sections(spec, "schema_version", "source", "sample", "outcome", "stats"),
          metadata_digest = digest
        )
      },
      runs$data_id[first], runs$spec[first]
    )))
  }
  # A grid without models still needs one (inert) item: a target cannot
  # branch over an empty one.
  none <- list(list(id = "none", none = TRUE))
  # The stamp (size and modification time) of each input file makes a branch
  # rerun when the data, frame, fit or simulation it reads has been rebuilt.
  if (identical(stage, "frame")) {
    keep <- !is.na(runs$fit_id) & !duplicated(runs$weather_id)
    items <- unname(Map(
      function(id, data_id, spec) {
        list(
          id = id, data_id = data_id, spec = sections(spec, "source", "weather", "seed"),
          data_file = data_file(data_id), stamps = list(data = .batch_stamp(data_file(data_id)))
        )
      },
      runs$weather_id[keep], runs$data_id[keep], runs$spec[keep]
    ))
    return(if (length(items)) items else none)
  }
  frame_file <- function(weather_id) {
    frames[match(weather_id, vapply(frame_specs, `[[`, "", "id"))]
  }
  if (identical(stage, "fit")) {
    keep <- !is.na(runs$fit_id) & !duplicated(runs$fit_id)
    items <- unname(Map(
      function(id, weather_id, data_id, spec) {
        files <- list(data = data_file(data_id), frame = frame_file(weather_id))
        list(
          id = id, weather_id = weather_id, data_id = data_id,
          spec = sections(spec, "sample", "model", "seed"),
          data_file = files$data, frame_file = files$frame, stamps = lapply(files, .batch_stamp)
        )
      },
      runs$fit_id[keep], runs$weather_id[keep], runs$data_id[keep], runs$spec[keep]
    ))
    return(if (length(items)) items else none)
  }
  if (identical(stage, "sim")) {
    keep <- !is.na(runs$sim_id) & !duplicated(runs$sim_id)
    items <- unname(Map(
      function(id, fit_id, weather_id, data_id, spec) {
        fit <- fits[[match(fit_id, vapply(fit_specs, `[[`, "", "id"))]]
        fit_file <- if (isTRUE(fit$ok)) fit$fit_file else NA_character_
        files <- list(data = data_file(data_id), frame = frame_file(weather_id), fit = fit_file)
        list(
          id = id, fit_id = fit_id, weather_id = weather_id, data_id = data_id,
          spec = sections(spec, "source", "sample", "outcome", "sim", "seed"),
          data_file = files$data, frame_file = files$frame, fit_file = fit_file,
          stamps = lapply(files, .batch_stamp),
          # The Step 2 run is stored for the policy branches that read it.
          needs_step2 = any(!is.na(runs$policy_id[runs$sim_id %in% id]))
        )
      },
      runs$sim_id[keep], runs$fit_id[keep], runs$weather_id[keep], runs$data_id[keep], runs$spec[keep]
    ))
    return(if (length(items)) items else none)
  }
  if (identical(stage, "policy")) {
    keep <- !is.na(runs$policy_id) & !duplicated(runs$policy_id)
    items <- unname(Map(
      function(id, sim_id, fit_id, spec) {
        sim <- sims[[match(sim_id, vapply(sim_specs, `[[`, "", "id"))]]
        fit <- fits[[match(fit_id, vapply(fit_specs, `[[`, "", "id"))]]
        sim_file <- if (isTRUE(sim$ok)) sim$sim_file else NA_character_
        fit_file <- if (isTRUE(fit$ok)) fit$fit_file else NA_character_
        list(
          id = id, sim_id = sim_id, fit_id = fit_id,
          spec = sections(spec, "sample", "policy", "seed"),
          sim_file = sim_file, fit_file = fit_file,
          stamps = list(sim = .batch_stamp(sim_file), fit = .batch_stamp(fit_file))
        )
      },
      runs$policy_id[keep], runs$sim_id[keep], runs$fit_id[keep], runs$spec[keep]
    ))
    return(if (length(items)) items else none)
  }
  items <- list()
  for (i in seq_len(nrow(runs))) {
    for (v in names(runs$wxvar_ids[[i]])) {
      id <- runs$wxvar_ids[[i]][[v]]
      if (is.null(items[[id]])) {
        spec <- runs$spec[[i]]
        items[[id]] <- list(
          id = id, variable = v, data_id = runs$data_id[i],
          spec = list(
            source = spec$source, stats = spec$stats,
            weather = c(spec$weather[v], list(hist_years = spec$weather$hist_years))
          ),
          data_file = data_file(runs$data_id[i]),
          stamps = list(data = .batch_stamp(data_file(runs$data_id[i])))
        )
      }
    }
  }
  unname(items)
}

# Size and modification time of a file, `NULL` when there is none.
#' @noRd
.batch_stamp <- function(path) {
  if (is.character(path) && length(path) == 1L && !is.na(path) && file.exists(path)) {
    c(size = file.size(path), mtime = as.numeric(file.mtime(path)))
  }
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
      # Continuous variables: the seed only matters for K-means bin breaks.
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
#' `model_terms`, `model_fit` and `model_vcov`. The slim copy of the fit that
#' Step 2 takes (`step2_slim_model_fit()`) goes to a file in the targets store
#' for the simulation branches.
#'
#' @param item A fit item from `wise_batch_unique()`.
#' @return A list: `ok`, `id`, `tables`, `provenance` (one row), `fit_file`; or
#'   a failure record.
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
      fit_file <- file.path(.batch_dir("fits"), paste0(item$id, ".qs2"))
      qs2::qs_save(
        list(mf = step2_slim_model_fit(mf), model_vars = model_term_names(m$selected_model)),
        fit_file
      )
      list(
        ok = TRUE, id = item$id, fit_file = fit_file,
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

#' Run Step 2 for one simulation specification and build its tables
#'
#' The batch counterpart of pressing "Run simulation": the baseline survey, the
#' historical and projection periods and the model fit of the fit stage go
#' through `wise_step2_input()` and the serial `step2_compute()` (weather kept
#' in memory, no workers), then the tables `annual`, `summary` and
#' `sim_weather`. The run itself is not kept.
#'
#' @param item A sim item from `wise_batch_unique()`.
#' @param connection_params Connection (default: the environment's).
#' @return A list: `ok`, `id`, `tables`, `provenance` (one row), `partial`
#'   (the members or scenarios that failed, as text); or a failure record.
#' @keywords internal
#' @export
wise_batch_sim <- function(item, connection_params = NULL) {
  skipped <- function(message) {
    list(ok = FALSE, stage = "sim", id = item$id, skipped = TRUE, message = message)
  }
  if (isTRUE(item$none)) {
    return(skipped("No simulation in the grid."))
  }
  d <- qs2::qs_read(item$data_file)
  if (!isTRUE(d$ok)) {
    return(skipped("The data stage failed."))
  }
  w <- qs2::qs_read(item$frame_file)
  if (!isTRUE(w$ok)) {
    return(if (isTRUE(w$skipped)) skipped(w$message) else w)
  }
  if (is.na(item$fit_file) || !file.exists(item$fit_file)) {
    return(skipped("The model fit failed."))
  }
  tryCatch(
    {
      t0 <- Sys.time()
      invisible(gc(reset = TRUE))
      spec <- item$spec
      sim <- spec$sim
      cp <- connection_params %||% wise_batch_connection(spec$source)
      mf <- qs2::qs_read(item$fit_file)$mf
      sw <- w$selected_weather
      input <- wise_step2_input(
        sw, wise_outcome_run_line(d$outcome$so, spec$outcome),
        svy = step2_baseline_svy(w$survey_weather, sim$baseline_survey),
        ss = .step2_filter_baseline_surveys(d$selected_surveys, sim$baseline_survey),
        mf = mf, cp = cp, hist_years = sim$hist_years, periods = sim$future_periods,
        ssps = sim$ssps, residuals = sim$residuals, coef_uncertainty = sim$coef_uncertainty,
        propagate_all = sim$propagate_all_covariate_uncertainty,
        stored_breaks = w$stored_breaks, slim = FALSE
      )
      # The worker of the app normalises the input the same way before it calls
      # step2_compute() (dates and scenarios as character).
      # The simulation joins the weather of each location-month to every
      # household there, which is many-to-many by construction; dplyr's
      # warning for it is expected (the app logs it too) and not a result.
      out <- withCallingHandlers(
        step2_compute(
          .wise_step2_async_normalize_input(input), seed = spec$seed, run_id = item$id,
          weather_storage = "memory"
        ),
        warning = function(w) {
          if (grepl("many-to-many relationship", conditionMessage(w), fixed = TRUE)) {
            invokeRestart("muffleWarning")
          }
        }
      )
      result <- wise_step2_annotate(
        out$result, sw, sim$hist_years,
        step2_baseline_label(
          step2_baseline_choices(w$survey_weather, d$selected_surveys), sim$baseline_survey
        )
      )
      tables <- step2_batch_tables(result, skip_coef = input$skip_coef_draws, selected_weather = sw)
      code <- paste(spec$sample$countries, collapse = "+")
      add_id <- function(x) if (is.null(x)) NULL else cbind(sim_id = item$id, code = code, x)
      # The policy branches start from this run (hundreds of MB; the constant
      # household vectors are written once).
      sim_file <- NA_character_
      if (isTRUE(item$needs_step2)) {
        sim_file <- file.path(.batch_dir("sims"), paste0(item$id, ".qs2"))
        qs2::qs_save(
          step2_share_constants(list(
            hist_sim_result = result$hist_sim_result, new_scenarios = result$new_scenarios,
            skip_coef = input$skip_coef_draws
          )),
          sim_file
        )
      }
      gc_max <- gc()
      failures <- vapply(result$failures %||% list(), function(f) {
        sprintf("%s: %s", f$key, wise_user_error(f$error %||% "failed", "batch simulation member"))
      }, character(1))
      list(
        ok = TRUE, id = item$id, partial = failures, sim_file = sim_file,
        tables = lapply(tables, add_id),
        provenance = data.frame(
          stage = "sim", id = item$id,
          n_rows = length(result$hist_sim_result$pipeline$y_point),
          n_surveys = nrow(d$selected_surveys),
          source_type = d$source$type, source_origin = d$source$origin,
          source_files = d$source$files, n_scenarios = length(result$new_scenarios),
          n_failed_keys = length(failures), r_peak_mb = sum(gc_max[, ncol(gc_max)]),
          seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")),
          stringsAsFactors = FALSE
        )
      )
    },
    error = function(e) .batch_failure("sim", item$id, e)
  )
}


#' Run Step 3 for one policy specification and build its tables
#'
#' The batch counterpart of pressing "Run simulation" in Step 3: the lever
#' configurations of the policy section go through `wise_policy_configs()` and
#' `wise_step3_input()` into the serial `step3_compute()` on the stored Step 2
#' run (no workers), under the R default random number generator; then
#' `step3_batch_tables()` builds the policy arm of `annual` and `summary`, the
#' `decomposition` and `policy_measures`. The run itself is not kept.
#'
#' @param item A policy item from `wise_batch_unique()`.
#' @return A list: `ok`, `id`, `tables`, `provenance` (one row), `partial`
#'   (metrics whose views failed, as text); or a failure record.
#' @keywords internal
#' @export
wise_batch_policy <- function(item) {
  skipped <- function(message) {
    list(ok = FALSE, stage = "policy", id = item$id, skipped = TRUE, message = message)
  }
  if (isTRUE(item$none)) {
    return(skipped("No policy in the grid."))
  }
  if (is.na(item$sim_file)) {
    return(skipped("The simulation failed."))
  }
  if (!file.exists(item$sim_file)) {
    return(.batch_failure("policy", item$id, simpleError(paste(
      "The stored Step 2 run is missing (keep_step2 = FALSE, or the file was removed).",
      "Invalidate the simulation target (targets::tar_invalidate(sim_tables)) and run again."
    ))))
  }
  if (is.na(item$fit_file) || !file.exists(item$fit_file)) {
    return(skipped("The model fit failed."))
  }
  tryCatch(
    {
      t0 <- Sys.time()
      invisible(gc(reset = TRUE))
      spec <- item$spec
      unit <- spec$sample$unit
      stored <- step2_unshare_constants(qs2::qs_read(item$sim_file))
      hs <- stored$hist_sim_result
      ss <- stored$new_scenarios %||% list()
      skip_coef <- isTRUE(stored$skip_coef)
      fit <- qs2::qs_read(item$fit_file)
      # The seeded policy draws follow the app, whose main process runs under
      # the R default generator.
      old_rng <- RNGkind()
      on.exit(do.call(RNGkind, as.list(old_rng)), add = TRUE)
      RNGkind("Mersenne-Twister", "Inversion", "Rejection")

      svy <- ensure_outcome_column(hs$svy, hs$so)
      levers <- wise_policy_configs(spec$policy, hs$so, unit, step3_sector_defaults(svy), svy = svy)
      input <- wise_step3_input(
        svy = svy, mf = fit$mf, sp_cfg = levers$sp, infra_cfg = levers$infra,
        digital_cfg = levers$digital, labor_cfg = levers$labor, education_cfg = levers$education,
        model_vars = fit$model_vars, analysis_unit = unit, skip_coef = skip_coef,
        residuals = hs$residuals %||% "original", run_generation = 1L, seed = spec$seed
      )
      # Joined many-to-many by construction in the correction (as in the app).
      run <- withCallingHandlers(
        do.call(step3_compute, c(list(hs = hs, ss = ss), input)),
        warning = function(w) {
          if (grepl("many-to-many relationship", conditionMessage(w), fixed = TRUE)) {
            invokeRestart("muffleWarning")
          }
        }
      )
      out <- step3_batch_tables(run, hs, ss, svy, levers, skip_coef, unit)
      code <- paste(spec$sample$countries, collapse = "+")
      add_id <- function(x) {
        if (is.null(x) || !nrow(x)) {
          return(NULL)
        }
        x$policy_id <- item$id
        cbind(sim_id = item$sim_id, code = code, x[c("policy_id", setdiff(names(x), "policy_id"))])
      }
      partial <- out$partial
      if (!identical(out$status$status, "ok")) {
        partial <- c(partial, paste0("policy contrast unavailable: ", out$status$reason))
      }
      gc_max <- gc()
      list(
        ok = TRUE, id = item$id, partial = partial,
        tables = lapply(out$tables, add_id),
        provenance = data.frame(
          stage = "policy", id = item$id, n_rows = nrow(svy),
          n_surveys = NA_integer_, source_type = NA_character_, source_origin = NA_character_,
          source_files = NA_character_, n_scenarios = length(ss), n_failed_keys = length(partial),
          r_peak_mb = sum(gc_max[, ncol(gc_max)]),
          seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")),
          stringsAsFactors = FALSE
        )
      )
    },
    error = function(e) .batch_failure("policy", item$id, e)
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
    model_interactions = if (is.null(spec$model$interactions)) {
      NA_character_
    } else {
      paste(spec$model$interactions, collapse = ",")
    },
    model_policy_vars = if (is.null(spec$model$policy_vars)) {
      NA_character_
    } else {
      paste(spec$model$policy_vars, collapse = ",")
    },
    covariate_method = spec$model$covariates$method %||% NA_character_,
    covariates = if (is.null(spec$model)) NA_character_ else .spec_json(spec$model$covariates),
    sim_hist_from = spec$sim$hist_years[1] %||% NA_integer_,
    sim_hist_to = spec$sim$hist_years[2] %||% NA_integer_,
    sim_future_periods = if (is.null(spec$sim)) NA_character_ else .spec_json(spec$sim$future_periods),
    sim_ssps = if (is.null(spec$sim)) NA_character_ else paste(spec$sim$ssps, collapse = ","),
    sim_residuals = spec$sim$residuals %||% NA_character_,
    sim_coef_uncertainty = spec$sim$coef_uncertainty %||% NA,
    sim_baseline_survey = if (is.null(spec$sim$baseline_survey)) {
      NA_character_
    } else {
      paste(spec$sim$baseline_survey, collapse = ",")
    },
    policy_levers = if (is.null(spec$policy)) NA_character_ else paste(names(spec$policy), collapse = ","),
    policy = if (is.null(spec$policy)) NA_character_ else .spec_json(spec$policy),
    stringsAsFactors = FALSE
  )
}

# Write one table as a parquet dataset partitioned by country code, replacing
# what an earlier run left.
#' @noRd
.write_table <- function(tab, out_dir, name) {
  dir <- file.path(out_dir, "tables", name)
  if (is.null(tab) || !nrow(tab)) {
    unlink(dir, recursive = TRUE)
    return(invisible(NULL))
  }
  # Write beside the old dataset and swap, so a failed write keeps it.
  tmp <- paste0(dir, ".new")
  unlink(tmp, recursive = TRUE)
  arrow::write_dataset(tab, tmp, format = "parquet", partitioning = "code")
  unlink(dir, recursive = TRUE)
  file.rename(tmp, dir)
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

#' SHA-256 of the survey files of the run's economies
#'
#' Local data folders only: other sources return `NULL`. Hashes the parquet
#' files under `microdata/` whose names start with an economy code of the runs.
#' With `cache_file`, a digest is reused while the size and modification time of
#' its file are unchanged, so a rerun does not read the data again.
#' @noRd
.batch_data_digest <- function(path, runs, cache_file = NULL) {
  if (!nzchar(path %||% "") || !dir.exists(file.path(path, "microdata"))) {
    return(NULL)
  }
  codes <- unique(unlist(lapply(runs$spec, function(s) s$sample$countries)))
  files <- list.files(file.path(path, "microdata"), pattern = "\\.parquet$", recursive = TRUE)
  files <- files[grepl(paste0("^(", paste(codes, collapse = "|"), ")_"), basename(files))]
  files <- sort(files)
  if (!length(files)) {
    return(NULL)
  }
  cache <- if (!is.null(cache_file) && file.exists(cache_file)) {
    tryCatch(readRDS(cache_file), error = function(e) NULL)
  }
  full <- file.path(path, "microdata", files)
  stamps <- paste(file.size(full), as.numeric(file.mtime(full)))
  sha <- vapply(seq_along(files), function(i) {
    hit <- cache[[files[i]]]
    if (!is.null(hit) && identical(hit$stamp, stamps[i])) {
      hit$sha256
    } else {
      digest::digest(file = full[i], algo = "sha256")
    }
  }, "")
  if (!is.null(cache_file)) {
    saveRDS(
      stats::setNames(Map(function(s, h) list(stamp = s, sha256 = h), stamps, sha), files),
      cache_file
    )
  }
  data.frame(file = files, sha256 = sha, row.names = NULL)
}

#' Write the results store
#'
#' @param out_dir Results folder.
#' @param grid Result of `wise_batch_grid()`.
#' @param data_tables,weather_tables,fit_tables,sim_tables,policy_tables Branch
#'   results.
#' @param keep_step2 Keep the stored Step 2 runs of the simulations that have a
#'   policy (see `wise_targets()`); runs of simulations that left the grid are
#'   removed either way.
#' @return `out_dir` (a `targets` file target).
#' @keywords internal
#' @export
wise_batch_write <- function(out_dir, grid, data_tables, weather_tables, fit_tables = list(),
                             sim_tables = list(), policy_tables = list(), keep_step2 = TRUE) {
  .need_pkg("arrow", "write result tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  runs <- grid$runs
  ok <- function(x) Filter(function(b) isTRUE(b$ok), x)
  pick <- function(branches, name) {
    dplyr::bind_rows(lapply(ok(branches), function(b) b$tables[[name]]))
  }
  # A stage the grid does not use holds one inert "none" item.
  n_items <- function(branches) sum(!vapply(branches, function(b) identical(b$id, "none"), logical(1)))

  # Stored Step 2 runs: drop those no policy of the grid reads (all of them
  # unless they are kept).
  wanted <- if (isTRUE(keep_step2)) unique(runs$sim_id[!is.na(runs$policy_id)]) else character(0)
  stored <- list.files(.batch_dir("sims"), pattern = "\\.qs2$", full.names = TRUE)
  unlink(stored[!sub("\\.qs2$", "", basename(stored)) %in% wanted], force = TRUE)

  .write_table(pick(data_tables, "variable_stats"), out_dir, "variable_stats")
  .write_table(pick(data_tables, "interview_dates"), out_dir, "interview_dates")
  .write_table(pick(weather_tables, "weather_stats"), out_dir, "weather_stats")
  for (name in c("model_terms", "model_fit", "model_vcov")) {
    .write_table(pick(fit_tables, name), out_dir, name)
  }
  # The baseline arm (policy_id NA) comes from the simulations, the policy arms
  # from the policy runs.
  for (name in c("annual", "summary")) {
    .write_table(
      dplyr::bind_rows(pick(sim_tables, name), pick(policy_tables, name)), out_dir, name
    )
  }
  .write_table(pick(sim_tables, "sim_weather"), out_dir, "sim_weather")
  for (name in c("decomposition", "policy_measures")) {
    .write_table(pick(policy_tables, name), out_dir, name)
  }

  # Run catalogue and per-run specs.
  flat <- dplyr::bind_rows(lapply(runs$spec, .spec_flat))
  axes <- setdiff(names(runs), .RESERVED_AXES)
  labels <- tibble::as_tibble(runs[axes])
  names(labels) <- paste0("axis_", axes)
  catalogue <- dplyr::bind_cols(
    tibble::as_tibble(runs[c("run_id", "data_id")]), labels,
    tibble::tibble(wxvar_ids = lapply(runs$wxvar_ids, unname)),
    tibble::as_tibble(runs[c("weather_id", "fit_id", "sim_id", "policy_id")]),
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
    c(ok(data_tables), ok(weather_tables), ok(fit_tables), ok(sim_tables), ok(policy_tables)),
    function(b) b$provenance
  ))
  prov$wiseapp_version <- as.character(utils::packageVersion("wiseapp"))
  prov$completed_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  arrow::write_parquet(prov, file.path(out_dir, "provenance.parquet"))

  failed <- Filter(
    function(b) is.list(b) && !isTRUE(b$ok) && !isTRUE(b$skipped),
    c(data_tables, weather_tables, fit_tables, sim_tables, policy_tables)
  )
  # A simulation that finished without some climate-model members or scenarios
  # keeps its tables and is listed as a partial failure.
  partial <- lapply(Filter(function(b) isTRUE(b$ok) && length(b$partial), sim_tables), function(b) {
    list(
      ok = FALSE, stage = "sim", id = b$id, error_class = "partial_simulation_failure",
      message = paste(b$partial, collapse = "; ")
    )
  })
  # A policy run whose contrast is unavailable (binary outcomes) or whose views
  # failed for some metrics keeps its tables and is listed the same way.
  partial_policy <- lapply(Filter(function(b) isTRUE(b$ok) && length(b$partial), policy_tables), function(b) {
    list(
      ok = FALSE, stage = "policy", id = b$id, error_class = "partial_policy_failure",
      message = paste(b$partial, collapse = "; ")
    )
  })
  failed <- c(failed, partial, partial_policy)
  # Fit branches that share a failed weather frame report it once.
  failed <- failed[!duplicated(vapply(failed, function(b) paste(b$stage, b$id), ""))]
  failures <- dplyr::bind_rows(lapply(failed, function(b) {
    affected <- switch(b$stage,
      data = runs$run_id[runs$data_id == b$id],
      frame = runs$run_id[runs$weather_id == b$id],
      fit = runs$run_id[runs$fit_id %in% b$id],
      sim = runs$run_id[runs$sim_id %in% b$id],
      policy = runs$run_id[runs$policy_id %in% b$id],
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
    data_files = grid$data_files,
    started_at = format(grid$started, "%Y-%m-%dT%H:%M:%S%z"),
    finished_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    n_runs = nrow(runs), n_data_sets = length(data_tables), n_weather_variables = length(weather_tables),
    n_fits = n_items(fit_tables), n_sims = n_items(sim_tables), n_policies = n_items(policy_tables),
    n_failures = nrow(failures),
    tables = as.list(tables)
  )
  writeLines(
    jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE, na = "null", null = "null"),
    file.path(out_dir, "manifest.json")
  )
  out_dir
}
