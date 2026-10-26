# Aggregation workspace helpers of the Step 2 results module ----
# Pure helpers moved out of mod_2_02_results_server() (CR-CQ-01). The cache
# workspace `ws` is a list of environments built in the module; the builders
# take the module's reactives (`bandwidth_p0`, `agg_methods`) and the shared
# cache as arguments and call them lazily, exactly as the closures did.

# Value-affecting aggregation inputs ----
# The aggregation cache is keyed by the inputs each method actually
# consumes (PERF-30), so moving the coefficient-band or poverty-line
# control only invalidates the methods that read it. band_q is display-
# only: aggregate_with_uncertainty_delta() applies it to value_lo/hi,
# which no builder below consumes - the band is re-derived from the
# cached SDs at render time. Display uses a fixed neutral pair.
AGG_BAND_Q <- c(lo = 0.10, hi = 0.90)
.POV_LINE_METHODS <- c("headcount_ratio", "gap", "fgt2")
.BANDWIDTH_METHODS <- "headcount_ratio"

.clear_workspace_cache <- function(ws) {
  if (is.null(ws)) {
    return(invisible(NULL))
  }
  if (is.environment(ws$cache)) {
    cached <- ls(ws$cache, all.names = TRUE)
    if (length(cached)) rm(list = cached, envir = ws$cache)
  }
  if (is.environment(ws$cache_order)) {
    ws$cache_order$keys <- character(0)
    ws$cache_order$hits <- 0L
    ws$cache_order$misses <- 0L
    ws$cache_order$evictions <- character(0)
  }
  if (is.environment(ws$prep_cache)) {
    ws$prep_cache$entries <- list()
    ws$prep_cache$keys <- character(0)
  }
  if (is.environment(ws$weighted_suite_cache)) {
    cached_suites <- ls(ws$weighted_suite_cache, all.names = TRUE)
    if (length(cached_suites)) {
      rm(list = cached_suites, envir = ws$weighted_suite_cache)
    }
    attr(ws$weighted_suite_cache, "keys") <- character(0)
  }
  invisible(NULL)
}

.cache_touch <- function(ws, key) {
  order <- ws$cache_order
  order$keys <- c(setdiff(order$keys, key), key)
  invisible(NULL)
}

.cache_get <- function(ws, key) {
  if (!exists(key, envir = ws$cache, inherits = FALSE)) {
    ws$cache_order$misses <- ws$cache_order$misses + 1L
    return(list(found = FALSE, value = NULL))
  }
  ws$cache_order$hits <- ws$cache_order$hits + 1L
  .cache_touch(ws, key)
  list(found = TRUE, value = get(key, envir = ws$cache, inherits = FALSE))
}

.cache_put <- function(ws, key, value) {
  assign(key, value, envir = ws$cache)
  .cache_touch(ws, key)
  while (length(ws$cache_order$keys) > ws$cache_order$max_entries) {
    old <- ws$cache_order$keys[[1L]]
    ws$cache_order$keys <- ws$cache_order$keys[-1L]
    if (exists(old, envir = ws$cache, inherits = FALSE)) {
      rm(list = old, envir = ws$cache)
      ws$cache_order$evictions <- c(ws$cache_order$evictions, old)
    }
  }
  invisible(value)
}

# CR-CQ-03: the weighted-suite cache is bounded like the others. Keys are
# kept in use order in an attribute of the environment; the oldest go first.
.SUITE_CACHE_MAX <- 32L

get_suite <- function(ws, key) {
  cache <- ws$weighted_suite_cache
  value <- get0(key, envir = cache, inherits = FALSE)
  if (!is.null(value)) attr(cache, "keys") <- c(setdiff(attr(cache, "keys"), key), key)
  value
}

assign_suite <- function(ws, key, value) {
  cache <- ws$weighted_suite_cache
  assign(key, value, envir = cache)
  keys <- c(setdiff(attr(cache, "keys"), key), key)
  while (length(keys) > .SUITE_CACHE_MAX) {
    rm(list = keys[[1L]], envir = cache)
    keys <- keys[-1L]
  }
  attr(cache, "keys") <- keys
  invisible(value)
}

.aggregation_cache_snapshot <- function(ws) {
  if (is.null(ws)) {
    return(list(
      keys = character(0), n_entries = 0L, max_entries = 0L,
      hits = 0L, misses = 0L, evictions = character(0),
      object_bytes = 0, serialized_bytes = 0,
      entry_object_bytes = numeric(0)
    ))
  }
  keys <- ws$cache_order$keys
  values <- if (length(keys)) {
    lapply(keys, get, envir = ws$cache, inherits = FALSE)
  } else {
    list()
  }
  object_bytes <- if (length(values)) {
    sum(vapply(values, function(x) as.numeric(utils::object.size(x)), numeric(1)))
  } else {
    0
  }
  serialized_bytes <- tryCatch(
    length(serialize(values, NULL, version = 3L)),
    error = function(e) NA_real_
  )
  list(
    keys = keys,
    n_entries = length(keys),
    max_entries = ws$cache_order$max_entries,
    hits = ws$cache_order$hits,
    misses = ws$cache_order$misses,
    evictions = ws$cache_order$evictions,
    object_bytes = object_bytes,
    serialized_bytes = serialized_bytes,
    entry_object_bytes = if (length(values)) {
      stats::setNames(
        vapply(values, function(x) as.numeric(utils::object.size(x)), numeric(1)),
        keys
      )
    } else {
      numeric(0)
    }
  )
}

# Cache-key suffix for the poverty line / bandwidth values a method reads.
# Methods that ignore them get a constant key so moving the poverty-line
# slider does not force their recomputation.
.pl_bw_key <- function(method, pl_v, bw) {
  parts <- character(0)
  if (method %in% .POV_LINE_METHODS) parts <- c(parts, format(pl_v))
  if (method %in% .BANDWIDTH_METHODS) parts <- c(parts, format(bw))
  if (length(parts) == 0L) "" else paste0("_", paste(parts, collapse = "_"))
}

.new_lazy_aggregation_method_list <- function(builder, method) {
  state <- new.env(parent = emptyenv())
  state$builder <- builder
  state$value <- NULL
  state$built <- FALSE
  structure(
    setNames(list(NULL), method),
    class = c("wise_lazy_aggregation_method_list", "list"),
    state = state
  )
}

.build_lazy_aggregation_method <- function(builder, method) {
  .new_lazy_aggregation_method_list(builder, method)
}

.lazy_aggregation_value <- function(x) {
  if (inherits(x, "wise_lazy_aggregation_method_list")) {
    state <- attr(x, "state", exact = TRUE)
    if (!isTRUE(state$built)) .force_lazy_aggregation_method(x)
    return(state$value)
  }
  x
}

.lazy_aggregation_table <- function(x, method) {
  value <- .lazy_aggregation_value(x)
  if (is.list(value) && !is.null(value[[method]])) value[[method]] else value
}

.seeded_lazy <- function(tbl, method) {
  x <- .new_lazy_aggregation_method_list(function() NULL, method)
  state <- attr(x, "state", exact = TRUE)
  state$value <- setNames(list(tbl), method)
  state$built <- TRUE
  x
}

.build_hist_for_method <- function(ws, method, pl_v, bandwidth_p0, agg_methods,
                                  shared_aggregation_cache) {
  pl <- ws$hs$pipeline
  bq <- AGG_BAND_Q
  is_log <- isTRUE(ws$hs$so$transform == "log")
   build_for <- function(weighted) {
         if ((isTRUE(weighted) || !isTRUE(has_w)) && !identical(method, "prosperity_gap")) {
          # R2-PERF-04: line-free and line-dependent metrics are separate suites.
          group <- .aggregation_suite_group(method, agg_methods())
          suite_pov <- if (group$poverty_dependent) pl_v %||% 3 else "none"
          suite_key <- paste0(
            "hist_suite_", weighted, "_", format(suite_pov), "_", format(bandwidth_p0()), "_",
            group$poverty_dependent
          )
        shared_key <- shared_aggregation_cache_key(
          ws$hs$.sig %||% list(pipeline = "step2"), suite_pov,
          bandwidth_p0(), weighted, ws$res, ws$skip, is_log, group$methods,
          seed = .step2_run_seed(ws$hs)
        )
        suite <- shared_aggregation_cache_get(shared_aggregation_cache, shared_key)
        if (!is.null(suite)) return(setNames(list(suite[[method]]), method))
        suite <- get_suite(ws, suite_key)
       if (is.null(suite)) {
         suite <- aggregate_pipeline_tables_multi(
           pipelines = pl,
           methods = group$methods,
           weighted = weighted,
            pov_lines = setNames(lapply(group$methods, function(x) pl_v %||% 3), group$methods),
           residuals = ws$res,
           is_log = is_log,
           band_q = bq,
           skip_coef = ws$skip,
           bandwidth_p0 = bandwidth_p0(),
           model_ids = "Historical",
           scenario = "Historical",
           shared_context = ws$hs$shared_context,
           preparation_cache = ws$prep_cache,
           seed = .step2_run_seed(ws$hs)
          )
          assign_suite(ws, suite_key, suite)
          shared_aggregation_cache_put(shared_aggregation_cache, shared_key, suite)
       }
       out <- suite[[method]]
       return(setNames(list(out), method))
     }
     out <- aggregate_pipeline_table(
      pipelines = pl,
      method = method,
      weighted = weighted,
       pov_line = pl_v,
      residuals = ws$res,
      is_log = is_log,
      band_q = bq,
      skip_coef = ws$skip,
      bandwidth_p0 = bandwidth_p0(),
      model_ids = "Historical",
      scenario = "Historical",
      shared_context = ws$hs$shared_context,
      preparation_cache = ws$prep_cache,
      seed = .step2_run_seed(ws$hs)
     )
    setNames(list(out), method)
   }
   has_w <- !is.null(pl$weight)
  list(
    unweighted = .build_lazy_aggregation_method(
      function() build_for(FALSE), method
    ),
    weighted = .build_lazy_aggregation_method(
      if (has_w) function() build_for(TRUE) else function() build_for(FALSE),
      method
    )
  )
}

.build_scn_for_method <- function(ws, method, pl_v, bandwidth_p0, agg_methods) {
  sc <- ws$sc
  if (length(sc) == 0L) {
    return(NULL)
  }
  bq <- AGG_BAND_Q
  setNames(lapply(seq_along(sc), function(s_idx) {
    s <- sc[[s_idx]]
    pipes <- s$pipelines
    is_log <- isTRUE(s$so$transform == "log")
    has_w <- !is.null(pipes[[1L]]$weight)
     build_for <- function(weighted) {
         if ((isTRUE(weighted) || !isTRUE(has_w)) && !identical(method, "prosperity_gap")) {
          group <- .aggregation_suite_group(method, agg_methods())
          suite_pov <- if (group$poverty_dependent) pl_v %||% 3 else "none"
          suite_key <- paste0(
            "scenario_suite_", names(sc)[[s_idx]], "_", format(suite_pov), "_", format(bandwidth_p0()), "_",
            group$poverty_dependent
          )
         suite <- get_suite(ws, suite_key)
         if (is.null(suite)) {
           suite <- aggregate_pipeline_tables_multi(
             pipelines = pipes,
             methods = group$methods,
             weighted = weighted,
              pov_lines = setNames(lapply(group$methods, function(x) pl_v %||% 3), group$methods),
             residuals = ws$res,
             is_log = is_log,
             band_q = bq,
             skip_coef = ws$skip,
             bandwidth_p0 = bandwidth_p0(),
             model_ids = names(pipes) %||% paste0("m", seq_along(pipes)),
             shared_context = s$shared_context,
             preparation_cache = ws$prep_cache,
             seed = .step2_run_seed(ws$hs)
           )
           assign_suite(ws, suite_key, suite)
         }
         out <- suite[[method]]
         return(setNames(list(out), method))
       }
       out <- aggregate_pipeline_table(
        pipelines = pipes,
        method = method,
        weighted = weighted,
          pov_line = pl_v,
        residuals = ws$res,
        is_log = is_log,
        band_q = bq,
        skip_coef = ws$skip,
        bandwidth_p0 = bandwidth_p0(),
        model_ids = names(pipes) %||% paste0("m", seq_along(pipes)),
        shared_context = s$shared_context,
        preparation_cache = ws$prep_cache,
        seed = .step2_run_seed(ws$hs)
      )
      setNames(list(out), method)
    }
    list(
      unweighted = .build_lazy_aggregation_method(
        function() build_for(FALSE), method
      ),
      weighted = .build_lazy_aggregation_method(
        if (has_w) function() build_for(TRUE) else function() build_for(FALSE),
        method
      )
    )
  }), names(sc))
}
