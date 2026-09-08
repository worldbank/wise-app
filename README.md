
<!-- README.md is generated from README.Rmd. Please edit that file -->

# `{wiseapp}`

<!-- badges: start -->

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

## Installation

You can install the development version of `{wiseapp}` like so:

``` r
# FILL THIS IN! HOW CAN PEOPLE INSTALL YOUR DEV PACKAGE?
```

## Run

You can launch the application by running:

``` r
wiseapp::run_app()
```

## About

You are reading the doc about version : 0.1.0

This README has been compiled on the

``` r
Sys.time()
#> [1] "2026-09-08 10:51:30 UTC"
```

Here are the tests results and package coverage:

``` r
devtools::check(quiet = TRUE)
#> ℹ Loading wiseapp
#> ── R CMD check results ────────────────────────────────────── wiseapp 0.1.0 ────
#> Duration: 3m 13.4s
#> 
#> ❯ checking tests ...
#>   See below...
#> 
#> ❯ checking for unstated dependencies in ‘tests’ ... WARNING
#>   '::' or ':::' imports not declared from:
#>     ‘arrow’ ‘bit64’
#> 
#> ❯ checking for future file timestamps ... NOTE
#>   unable to verify current time
#> 
#> ❯ checking top-level files ... NOTE
#>   Non-standard files/directories found at top level:
#>     ‘README.html’ ‘Rplots.pdf’
#> 
#> ❯ checking dependencies in R code ... NOTE
#>   Namespaces in Imports field not imported from:
#>     ‘brand.yml’ ‘parsnip’ ‘pkgload’ ‘ragg’ ‘ranger’ ‘xgboost’
#>     All declared Imports should be used.
#> 
#> ❯ checking R code for possible problems ... [17s/19s] NOTE
#>   .add_sim_timestamp_fields: no visible binding for global variable
#>     ‘year’
#>   .apply_transformations: no visible binding for global variable ‘year’
#>   bottom_code_welfare: no visible binding for global variable ‘welfare’
#>   fct_run_simulation: no visible binding for global variable ‘year’
#>   get_weather: no visible binding for global variable ‘year’
#>   get_weather : .process_ssp: no visible binding for global variable
#>     ‘year’
#>   loc_panel: no visible binding for global variable ‘weight’
#>   loc_panel: no visible binding for global variable ‘weight_x’
#>   loc_panel: no visible binding for global variable ‘weight_y’
#>   mod_1_02_surveystats_server : <anonymous>: no visible binding for
#>     global variable ‘survey_stats’
#>   mod_1_02_surveystats_server : <anonymous>: no visible binding for
#>     global variable ‘year’
#>   mod_1_02_surveystats_server : <anonymous>: no visible binding for
#>     global variable ‘g’
#>   mod_1_02_surveystats_server : <anonymous>: no visible global function
#>     definition for ‘st_extent’
#>   mod_1_02_surveystats_server : <anonymous>: no visible global function
#>     definition for ‘st_xmin’
#>   mod_1_02_surveystats_server : <anonymous>: no visible binding for
#>     global variable ‘env’
#>   mod_1_02_surveystats_server : <anonymous>: no visible global function
#>     definition for ‘st_ymin’
#>   mod_1_02_surveystats_server : <anonymous>: no visible global function
#>     definition for ‘st_xmax’
#>   mod_1_02_surveystats_server : <anonymous>: no visible global function
#>     definition for ‘st_ymax’
#>   mod_1_05_weatherstats_server : <anonymous>: no visible binding for
#>     global variable ‘weather_stats’
#>   mod_1_05_weatherstats_server : <anonymous> : weather_dist_fig :
#>     <anonymous>: no visible binding for global variable ‘year’
#>   mod_1_05_weatherstats_server : <anonymous> : make_weather_dist: no
#>     visible binding for global variable ‘year’
#>   mod_1_05_weatherstats_server : <anonymous> : weather_dist_cont_fig :
#>     <anonymous>: no visible binding for global variable ‘year’
#>   mod_1_05_weatherstats_server : <anonymous> : make_weather_dist_cont: no
#>     visible binding for global variable ‘year’
#>   mod_1_06_model_server : <anonymous>: no visible binding for global
#>     variable ‘run_model’
#>   mod_2_01_weathersim_server : <anonymous>: no visible binding for global
#>     variable ‘run_sim’
#>   plot_binscatter: no visible binding for global variable ‘x’
#>   plot_welfare_dist: no visible global function definition for ‘ave’
#>   prepare_hist_weather: no visible binding for global variable ‘year’
#>   resimulate_with_svy: no visible binding for global variable ‘year’
#>   run_sim_pipeline: no visible binding for global variable ‘year’
#>   Undefined global functions or variables:
#>     ave env g run_model run_sim st_extent st_xmax st_xmin st_ymax st_ymin
#>     survey_stats weather_stats weight weight_x weight_y welfare x year
#>   Consider adding
#>     importFrom("stats", "ave")
#>   to your NAMESPACE file.
#> 
#> ── Test failures ───────────────────────────────────────────────── testthat ────
#> 
#> > # This file is part of the standard setup for testthat.
#> > # It is recommended that you do not modify it.
#> > #
#> > # Where should you do additional test configuration?
#> > # Learn more about the roles of various files in:
#> > # * https://r-pkgs.org/testing-design.html#sec-tests-files-overview
#> > # * https://testthat.r-lib.org/articles/special-files.html
#> > 
#> > library(testthat)
#> > library(wiseapp)
#> > 
#> > test_check("wiseapp")
#> [active_mask] additive-decomposition SE active: keeping 1/3 coefficients (RIF engine). Active: tx
#> [active_mask] additive-decomposition SE active: keeping 1/3 coefficients (linear engine). Active: tx
#> [active_mask] additive-decomposition SE active: keeping 2/4 coefficients (linear engine). Active: tx, electricity
#> [active_mask] additive-decomposition SE active: keeping 1/3 coefficients (linear engine). Active: tx
#> [predict_rif] additive-decomposition mask applied: F_loading is 50 x 1 (out of 4 coefficients).
#> duckdb is storing downloaded extensions and secrets under ~/.duckdb:
#> i /Users/bbrunckhorst/.duckdb
#> This persists across sessions and is shared with the DuckDB CLI and other clients.
#> i Run duckdb(shared_home = FALSE) to use a temporary directory instead.
#> i See ?duckdb_storage for details and alternatives.
#> duckdb is storing downloaded extensions and secrets under ~/.duckdb:
#> i /Users/bbrunckhorst/.duckdb
#> This persists across sessions and is shared with the DuckDB CLI and other clients.
#> i Run duckdb(shared_home = FALSE) to use a temporary directory instead.
#> i See ?duckdb_storage for details and alternatives.
#> Saving _problems/test-determinism-232.R
#> Saving _problems/test-export-bundle-416.R
#> Saving _problems/test-export-bundle-435.R
#> duckdb is storing downloaded extensions and secrets under ~/.duckdb:
#> i /Users/bbrunckhorst/.duckdb
#> This persists across sessions and is shared with the DuckDB CLI and other clients.
#> i Run duckdb(shared_home = FALSE) to use a temporary directory instead.
#> i See ?duckdb_storage for details and alternatives.
#> duckdb is storing downloaded extensions and secrets under ~/.duckdb:
#> i /Users/bbrunckhorst/.duckdb
#> This persists across sessions and is shared with the DuckDB CLI and other clients.
#> i Run duckdb(shared_home = FALSE) to use a temporary directory instead.
#> i See ?duckdb_storage for details and alternatives.
#> duckdb is storing downloaded extensions and secrets under ~/.duckdb:
#> i /Users/bbrunckhorst/.duckdb
#> This persists across sessions and is shared with the DuckDB CLI and other clients.
#> i Run duckdb(shared_home = FALSE) to use a temporary directory instead.
#> i See ?duckdb_storage for details and alternatives.
#> duckdb is storing downloaded extensions and secrets under ~/.duckdb:
#> i /Users/bbrunckhorst/.duckdb
#> This persists across sessions and is shared with the DuckDB CLI and other clients.
#> i Run duckdb(shared_home = FALSE) to use a temporary directory instead.
#> i See ?duckdb_storage for details and alternatives.
#> Custom cutoffs for tx: 10.039, 20, 25, 30, 35, 39.998
#> Custom cutoffs for tx: 0, 20, 25, 30, 35, 100
#> Insufficient variation in tx. Keeping continuous.
#> Custom cutoffs for tx: 0, 20, 25, 100
#> K-means cutoffs for tx: 2.654, 9.843, 20.08, 27.058
#> K-means cutoffs for tx: 2.654, 9.843, 20.08, 27.058
#> K-means cutoffs for tx: 3.087, 10.082, 20.144, 27.543
#> duckdb is storing downloaded extensions and secrets under ~/.duckdb:
#> i /Users/bbrunckhorst/.duckdb
#> This persists across sessions and is shared with the DuckDB CLI and other clients.
#> i Run duckdb(shared_home = FALSE) to use a temporary directory instead.
#> i See ?duckdb_storage for details and alternatives.
#> duckdb is storing downloaded extensions and secrets under ~/.duckdb:
#> i /Users/bbrunckhorst/.duckdb
#> This persists across sessions and is shared with the DuckDB CLI and other clients.
#> i Run duckdb(shared_home = FALSE) to use a temporary directory instead.
#> i See ?duckdb_storage for details and alternatives.
#> duckdb is storing downloaded extensions and secrets under ~/.duckdb:
#> i /Users/bbrunckhorst/.duckdb
#> This persists across sessions and is shared with the DuckDB CLI and other clients.
#> i Run duckdb(shared_home = FALSE) to use a temporary directory instead.
#> i See ?duckdb_storage for details and alternatives.
#> [wiseapp] Coefficient draws skipped (point estimates only)
#> [wiseapp] Running simulation pipelines...
#> [wiseapp] Simulation complete in 0s total | weather: 0s | pipelines: 0s | 4 key(s) | ~4 runs
#> [wiseapp] Coefficient draws skipped (point estimates only)
#> [wiseapp] Running simulation pipelines...
#> [wiseapp] Coefficient draws skipped (point estimates only)
#> [wiseapp] Running simulation pipelines...
#> [wiseapp] Coefficient draws skipped (point estimates only)
#> [wiseapp] Running simulation pipelines...
#> [wiseapp] Simulation complete in 0s total | weather: 0s | pipelines: 0s | 4 key(s) | ~4 runs | 1 key(s) FAILED
#> [wiseapp] Coefficient draws skipped (point estimates only)
#> [wiseapp] Running simulation pipelines...
#> [wiseapp] Simulation complete in 0s total | weather: 0s | pipelines: 0s | 4 key(s) | ~4 runs | 2 key(s) FAILED
#> [ FAIL 3 | WARN 10 | SKIP 22 | PASS 1414 ]
#> 
#> ══ Skipped tests (22) ══════════════════════════════════════════════════════════
#> • {arrow} is not installed (22): 'test-determinism.R:59:3',
#>   'test-fct_get_weather.R:578:3', 'test-fct_get_weather.R:605:3',
#>   'test-fct_get_weather.R:624:3', 'test-fct_get_weather.R:644:3',
#>   'test-fct_get_weather.R:664:3', 'test-fct_get_weather.R:683:3',
#>   'test-fct_get_weather.R:711:3', 'test-fct_get_weather.R:741:3',
#>   'test-fct_get_weather.R:768:3', 'test-fct_get_weather.R:911:3',
#>   'test-fct_get_weather.R:943:3', 'test-fct_get_weather.R:1036:3',
#>   'test-fct_get_weather.R:1093:3', 'test-fct_get_weather.R:1122:3',
#>   'test-fct_get_weather.R:1170:3', 'test-fct_get_weather.R:1227:3',
#>   'test-fct_wx_cache.R:44:3', 'test-fct_wx_cache.R:71:3',
#>   'test-fct_wx_cache.R:94:3', 'test-fct_wx_cache.R:110:3',
#>   'test-fct_wx_cache.R:133:3'
#> 
#> ══ Warnings ════════════════════════════════════════════════════════════════════
#> ── Warning ('test-rerun-regressions.R:176:7'): re-running Step 2 reuses its Results tab instead of adding another ──
#> Unknown or uninitialised column: `Estimate`.
#> Backtrace:
#>       ▆
#>    1. ├─shiny::testServer(...) at test-rerun-regressions.R:166:3
#>    2. │ ├─shiny:::withMockContext(...)
#>    3. │ │ ├─shiny::isolate(...)
#>    4. │ │ │ ├─shiny::..stacktraceoff..(...)
#>    5. │ │ │ └─ctx$run(...)
#>    6. │ │ │   ├─promises::with_promise_domain(...)
#>    7. │ │ │   │ └─domain$wrapSync(expr)
#>    8. │ │ │   ├─shiny::withReactiveDomain(...)
#>    9. │ │ │   │ └─promises::with_promise_domain(...)
#>   10. │ │ │   │   └─domain$wrapSync(expr)
#>   11. │ │ │   │     └─base::force(expr)
#>   12. │ │ │   ├─shiny:::with_otel_span_context(...)
#>   13. │ │ │   │ └─base::force(expr)
#>   14. │ │ │   ├─shiny::captureStackTraces(...)
#>   15. │ │ │   │ └─promises::with_promise_domain(...)
#>   16. │ │ │   │   └─domain$wrapSync(expr)
#>   17. │ │ │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   18. │ │ │   └─env$runWith(self, func)
#>   19. │ │ │     └─shiny (local) contextFunc()
#>   20. │ │ │       └─shiny::..stacktraceon..(expr)
#>   21. │ │ ├─shiny::withReactiveDomain(...)
#>   22. │ │ │ └─promises::with_promise_domain(...)
#>   23. │ │ │   └─domain$wrapSync(expr)
#>   24. │ │ │     └─base::force(expr)
#>   25. │ │ └─withr::with_options(...)
#>   26. │ │   └─base::force(code)
#>   27. │ └─rlang::eval_tidy(quosure, mask, rlang::caller_env())
#>   28. └─session$flushReact() at test-rerun-regressions.R:176:7
#>   29.   └─private$flush()
#>   30.     └─shiny:::flushReact()
#>   31.       └─.getReactiveEnvironment()$flush()
#>   32.         └─ctx$executeFlushCallbacks()
#>   33.           └─base::lapply(...)
#>   34.             └─shiny (local) FUN(X[[i]], ...)
#>   35.               └─shiny (local) flushCallback()
#>   36.                 ├─shiny:::hybrid_chain(...)
#>   37.                 │ └─shiny (local) do()
#>   38.                 │   ├─base::tryCatch(...)
#>   39.                 │   │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   40.                 │   │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   41.                 │   │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   42.                 │   ├─shiny::captureStackTraces(...)
#>   43.                 │   │ └─promises::with_promise_domain(...)
#>   44.                 │   │   └─domain$wrapSync(expr)
#>   45.                 │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   46.                 │   ├─base::withVisible(force(expr))
#>   47.                 │   └─base::force(expr)
#>   48.                 ├─shiny:::shinyCallingHandlers(run())
#>   49.                 │ ├─base::withCallingHandlers(...)
#>   50.                 │ └─shiny::captureStackTraces(expr)
#>   51.                 │   └─promises::with_promise_domain(...)
#>   52.                 │     └─domain$wrapSync(expr)
#>   53.                 │       └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   54.                 └─shiny (local) run()
#>   55.                   └─ctx$run(.func)
#>   56.                     ├─promises::with_promise_domain(...)
#>   57.                     │ └─domain$wrapSync(expr)
#>   58.                     ├─shiny::withReactiveDomain(...)
#>   59.                     │ └─promises::with_promise_domain(...)
#>   60.                     │   └─domain$wrapSync(expr)
#>   61.                     │     └─base::force(expr)
#>   62.                     ├─shiny:::with_otel_span_context(...)
#>   63.                     │ └─base::force(expr)
#>   64.                     ├─shiny::captureStackTraces(...)
#>   65.                     │ └─promises::with_promise_domain(...)
#>   66.                     │   └─domain$wrapSync(expr)
#>   67.                     │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   68.                     └─env$runWith(self, func)
#>   69.                       └─shiny (local) contextFunc()
#>   70.                         ├─shiny::..stacktraceon..(`<observer>`(...))
#>   71.                         └─shiny (local) `<observer>`(...)
#>   72.                           └─shiny::observe()
#>   73.                             ├─base::tryCatch(...)
#>   74.                             │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   75.                             │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   76.                             │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   77.                             ├─private$withCurrentOutput(name, func(self, name))
#>   78.                             │ └─promises::with_promise_domain(...)
#>   79.                             │   └─domain$wrapSync(expr)
#>   80.                             │     └─base::force(expr)
#>   81.                             └─shiny (local) func(self, name)
#>   82.                               ├─shiny::..stacktraceoff..(if (is.null(formals(renderFunc))) renderFunc() else renderFunc(...))
#>   83.                               └─DT (local) renderFunc(...)
#>   84.                                 ├─promises::with_promise_domain(domain, renderFunc())
#>   85.                                 │ └─domain$wrapSync(expr)
#>   86.                                 │   └─base::force(expr)
#>   87.                                 └─shiny (local) renderFunc()
#>   88.                                   ├─shiny::..stacktraceoff..(if (is.null(formals(renderFunc))) renderFunc() else renderFunc(...))
#>   89.                                   └─shiny (local) renderFunc(...)
#>   90.                                     ├─shiny:::hybrid_chain(...)
#>   91.                                     │ └─shiny (local) do()
#>   92.                                     │   ├─base::tryCatch(...)
#>   93.                                     │   │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   94.                                     │   │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   95.                                     │   │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   96.                                     │   ├─shiny::captureStackTraces(...)
#>   97.                                     │   │ └─promises::with_promise_domain(...)
#>   98.                                     │   │   └─domain$wrapSync(expr)
#>   99.                                     │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>  100.                                     │   ├─base::withVisible(force(expr))
#>  101.                                     │   └─base::force(expr)
#>  102.                                     ├─shiny::..stacktraceon..(func())
#>  103.                                     └─shiny (local) func()
#>  104.                                       └─DT (local) `::\nhtmlwidgets\nshinyRenderWidget`()
#>  105.                                         └─DT (local) widgetFunc()
#>  106.                                           └─wiseapp (local) exprFunc()
#>  107.                                             ├─tbl[!grepl("^Ensemble |^Pooled ", tbl$Estimate), , drop = FALSE]
#>  108.                                             ├─tibble:::`[.tbl_df`(...)
#>  109.                                             ├─base::grepl("^Ensemble |^Pooled ", tbl$Estimate)
#>  110.                                             │ └─base::is.factor(x)
#>  111.                                             ├─tbl$Estimate
#>  112.                                             └─tibble:::`$.tbl_df`(tbl, Estimate)
#> ── Warning ('test-rerun-regressions.R:176:7'): re-running Step 2 reuses its Results tab instead of adding another ──
#> Unknown or uninitialised column: `Estimate`.
#> Backtrace:
#>       ▆
#>    1. ├─shiny::testServer(...) at test-rerun-regressions.R:166:3
#>    2. │ ├─shiny:::withMockContext(...)
#>    3. │ │ ├─shiny::isolate(...)
#>    4. │ │ │ ├─shiny::..stacktraceoff..(...)
#>    5. │ │ │ └─ctx$run(...)
#>    6. │ │ │   ├─promises::with_promise_domain(...)
#>    7. │ │ │   │ └─domain$wrapSync(expr)
#>    8. │ │ │   ├─shiny::withReactiveDomain(...)
#>    9. │ │ │   │ └─promises::with_promise_domain(...)
#>   10. │ │ │   │   └─domain$wrapSync(expr)
#>   11. │ │ │   │     └─base::force(expr)
#>   12. │ │ │   ├─shiny:::with_otel_span_context(...)
#>   13. │ │ │   │ └─base::force(expr)
#>   14. │ │ │   ├─shiny::captureStackTraces(...)
#>   15. │ │ │   │ └─promises::with_promise_domain(...)
#>   16. │ │ │   │   └─domain$wrapSync(expr)
#>   17. │ │ │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   18. │ │ │   └─env$runWith(self, func)
#>   19. │ │ │     └─shiny (local) contextFunc()
#>   20. │ │ │       └─shiny::..stacktraceon..(expr)
#>   21. │ │ ├─shiny::withReactiveDomain(...)
#>   22. │ │ │ └─promises::with_promise_domain(...)
#>   23. │ │ │   └─domain$wrapSync(expr)
#>   24. │ │ │     └─base::force(expr)
#>   25. │ │ └─withr::with_options(...)
#>   26. │ │   └─base::force(code)
#>   27. │ └─rlang::eval_tidy(quosure, mask, rlang::caller_env())
#>   28. └─session$flushReact() at test-rerun-regressions.R:176:7
#>   29.   └─private$flush()
#>   30.     └─shiny:::flushReact()
#>   31.       └─.getReactiveEnvironment()$flush()
#>   32.         └─ctx$executeFlushCallbacks()
#>   33.           └─base::lapply(...)
#>   34.             └─shiny (local) FUN(X[[i]], ...)
#>   35.               └─shiny (local) flushCallback()
#>   36.                 ├─shiny:::hybrid_chain(...)
#>   37.                 │ └─shiny (local) do()
#>   38.                 │   ├─base::tryCatch(...)
#>   39.                 │   │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   40.                 │   │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   41.                 │   │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   42.                 │   ├─shiny::captureStackTraces(...)
#>   43.                 │   │ └─promises::with_promise_domain(...)
#>   44.                 │   │   └─domain$wrapSync(expr)
#>   45.                 │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   46.                 │   ├─base::withVisible(force(expr))
#>   47.                 │   └─base::force(expr)
#>   48.                 ├─shiny:::shinyCallingHandlers(run())
#>   49.                 │ ├─base::withCallingHandlers(...)
#>   50.                 │ └─shiny::captureStackTraces(expr)
#>   51.                 │   └─promises::with_promise_domain(...)
#>   52.                 │     └─domain$wrapSync(expr)
#>   53.                 │       └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   54.                 └─shiny (local) run()
#>   55.                   └─ctx$run(.func)
#>   56.                     ├─promises::with_promise_domain(...)
#>   57.                     │ └─domain$wrapSync(expr)
#>   58.                     ├─shiny::withReactiveDomain(...)
#>   59.                     │ └─promises::with_promise_domain(...)
#>   60.                     │   └─domain$wrapSync(expr)
#>   61.                     │     └─base::force(expr)
#>   62.                     ├─shiny:::with_otel_span_context(...)
#>   63.                     │ └─base::force(expr)
#>   64.                     ├─shiny::captureStackTraces(...)
#>   65.                     │ └─promises::with_promise_domain(...)
#>   66.                     │   └─domain$wrapSync(expr)
#>   67.                     │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   68.                     └─env$runWith(self, func)
#>   69.                       └─shiny (local) contextFunc()
#>   70.                         ├─shiny::..stacktraceon..(`<observer>`(...))
#>   71.                         └─shiny (local) `<observer>`(...)
#>   72.                           └─shiny::observe()
#>   73.                             ├─base::tryCatch(...)
#>   74.                             │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   75.                             │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   76.                             │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   77.                             ├─private$withCurrentOutput(name, func(self, name))
#>   78.                             │ └─promises::with_promise_domain(...)
#>   79.                             │   └─domain$wrapSync(expr)
#>   80.                             │     └─base::force(expr)
#>   81.                             └─shiny (local) func(self, name)
#>   82.                               ├─shiny::..stacktraceoff..(if (is.null(formals(renderFunc))) renderFunc() else renderFunc(...))
#>   83.                               └─DT (local) renderFunc(...)
#>   84.                                 ├─promises::with_promise_domain(domain, renderFunc())
#>   85.                                 │ └─domain$wrapSync(expr)
#>   86.                                 │   └─base::force(expr)
#>   87.                                 └─shiny (local) renderFunc()
#>   88.                                   ├─shiny::..stacktraceoff..(if (is.null(formals(renderFunc))) renderFunc() else renderFunc(...))
#>   89.                                   └─shiny (local) renderFunc(...)
#>   90.                                     ├─shiny:::hybrid_chain(...)
#>   91.                                     │ └─shiny (local) do()
#>   92.                                     │   ├─base::tryCatch(...)
#>   93.                                     │   │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   94.                                     │   │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   95.                                     │   │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   96.                                     │   ├─shiny::captureStackTraces(...)
#>   97.                                     │   │ └─promises::with_promise_domain(...)
#>   98.                                     │   │   └─domain$wrapSync(expr)
#>   99.                                     │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>  100.                                     │   ├─base::withVisible(force(expr))
#>  101.                                     │   └─base::force(expr)
#>  102.                                     ├─shiny::..stacktraceon..(func())
#>  103.                                     └─shiny (local) func()
#>  104.                                       └─DT (local) `::\nhtmlwidgets\nshinyRenderWidget`()
#>  105.                                         └─DT (local) widgetFunc()
#>  106.                                           └─wiseapp (local) exprFunc()
#>  107.                                             ├─tbl[!grepl("^Ensemble |^Pooled ", tbl$Estimate), , drop = FALSE]
#>  108.                                             ├─tibble:::`[.tbl_df`(...)
#>  109.                                             ├─base::grepl("^Ensemble |^Pooled ", tbl$Estimate)
#>  110.                                             │ └─base::is.factor(x)
#>  111.                                             ├─tbl$Estimate
#>  112.                                             └─tibble:::`$.tbl_df`(tbl, Estimate)
#> ── Warning ('test-rerun-regressions.R:176:7'): re-running Step 2 reuses its Results tab instead of adding another ──
#> Unknown or uninitialised column: `Estimate`.
#> Backtrace:
#>       ▆
#>    1. ├─shiny::testServer(...) at test-rerun-regressions.R:166:3
#>    2. │ ├─shiny:::withMockContext(...)
#>    3. │ │ ├─shiny::isolate(...)
#>    4. │ │ │ ├─shiny::..stacktraceoff..(...)
#>    5. │ │ │ └─ctx$run(...)
#>    6. │ │ │   ├─promises::with_promise_domain(...)
#>    7. │ │ │   │ └─domain$wrapSync(expr)
#>    8. │ │ │   ├─shiny::withReactiveDomain(...)
#>    9. │ │ │   │ └─promises::with_promise_domain(...)
#>   10. │ │ │   │   └─domain$wrapSync(expr)
#>   11. │ │ │   │     └─base::force(expr)
#>   12. │ │ │   ├─shiny:::with_otel_span_context(...)
#>   13. │ │ │   │ └─base::force(expr)
#>   14. │ │ │   ├─shiny::captureStackTraces(...)
#>   15. │ │ │   │ └─promises::with_promise_domain(...)
#>   16. │ │ │   │   └─domain$wrapSync(expr)
#>   17. │ │ │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   18. │ │ │   └─env$runWith(self, func)
#>   19. │ │ │     └─shiny (local) contextFunc()
#>   20. │ │ │       └─shiny::..stacktraceon..(expr)
#>   21. │ │ ├─shiny::withReactiveDomain(...)
#>   22. │ │ │ └─promises::with_promise_domain(...)
#>   23. │ │ │   └─domain$wrapSync(expr)
#>   24. │ │ │     └─base::force(expr)
#>   25. │ │ └─withr::with_options(...)
#>   26. │ │   └─base::force(code)
#>   27. │ └─rlang::eval_tidy(quosure, mask, rlang::caller_env())
#>   28. └─session$flushReact() at test-rerun-regressions.R:176:7
#>   29.   └─private$flush()
#>   30.     └─shiny:::flushReact()
#>   31.       └─.getReactiveEnvironment()$flush()
#>   32.         └─ctx$executeFlushCallbacks()
#>   33.           └─base::lapply(...)
#>   34.             └─shiny (local) FUN(X[[i]], ...)
#>   35.               └─shiny (local) flushCallback()
#>   36.                 ├─shiny:::hybrid_chain(...)
#>   37.                 │ └─shiny (local) do()
#>   38.                 │   ├─base::tryCatch(...)
#>   39.                 │   │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   40.                 │   │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   41.                 │   │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   42.                 │   ├─shiny::captureStackTraces(...)
#>   43.                 │   │ └─promises::with_promise_domain(...)
#>   44.                 │   │   └─domain$wrapSync(expr)
#>   45.                 │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   46.                 │   ├─base::withVisible(force(expr))
#>   47.                 │   └─base::force(expr)
#>   48.                 ├─shiny:::shinyCallingHandlers(run())
#>   49.                 │ ├─base::withCallingHandlers(...)
#>   50.                 │ └─shiny::captureStackTraces(expr)
#>   51.                 │   └─promises::with_promise_domain(...)
#>   52.                 │     └─domain$wrapSync(expr)
#>   53.                 │       └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   54.                 └─shiny (local) run()
#>   55.                   └─ctx$run(.func)
#>   56.                     ├─promises::with_promise_domain(...)
#>   57.                     │ └─domain$wrapSync(expr)
#>   58.                     ├─shiny::withReactiveDomain(...)
#>   59.                     │ └─promises::with_promise_domain(...)
#>   60.                     │   └─domain$wrapSync(expr)
#>   61.                     │     └─base::force(expr)
#>   62.                     ├─shiny:::with_otel_span_context(...)
#>   63.                     │ └─base::force(expr)
#>   64.                     ├─shiny::captureStackTraces(...)
#>   65.                     │ └─promises::with_promise_domain(...)
#>   66.                     │   └─domain$wrapSync(expr)
#>   67.                     │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   68.                     └─env$runWith(self, func)
#>   69.                       └─shiny (local) contextFunc()
#>   70.                         ├─shiny::..stacktraceon..(`<observer>`(...))
#>   71.                         └─shiny (local) `<observer>`(...)
#>   72.                           └─shiny::observe()
#>   73.                             ├─base::tryCatch(...)
#>   74.                             │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   75.                             │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   76.                             │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   77.                             ├─private$withCurrentOutput(name, func(self, name))
#>   78.                             │ └─promises::with_promise_domain(...)
#>   79.                             │   └─domain$wrapSync(expr)
#>   80.                             │     └─base::force(expr)
#>   81.                             └─shiny (local) func(self, name)
#>   82.                               ├─shiny::..stacktraceoff..(if (is.null(formals(renderFunc))) renderFunc() else renderFunc(...))
#>   83.                               └─DT (local) renderFunc(...)
#>   84.                                 ├─promises::with_promise_domain(domain, renderFunc())
#>   85.                                 │ └─domain$wrapSync(expr)
#>   86.                                 │   └─base::force(expr)
#>   87.                                 └─shiny (local) renderFunc()
#>   88.                                   ├─shiny::..stacktraceoff..(if (is.null(formals(renderFunc))) renderFunc() else renderFunc(...))
#>   89.                                   └─shiny (local) renderFunc(...)
#>   90.                                     ├─shiny:::hybrid_chain(...)
#>   91.                                     │ └─shiny (local) do()
#>   92.                                     │   ├─base::tryCatch(...)
#>   93.                                     │   │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   94.                                     │   │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   95.                                     │   │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   96.                                     │   ├─shiny::captureStackTraces(...)
#>   97.                                     │   │ └─promises::with_promise_domain(...)
#>   98.                                     │   │   └─domain$wrapSync(expr)
#>   99.                                     │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>  100.                                     │   ├─base::withVisible(force(expr))
#>  101.                                     │   └─base::force(expr)
#>  102.                                     ├─shiny::..stacktraceon..(func())
#>  103.                                     └─shiny (local) func()
#>  104.                                       └─DT (local) `::\nhtmlwidgets\nshinyRenderWidget`()
#>  105.                                         └─DT (local) widgetFunc()
#>  106.                                           └─wiseapp (local) exprFunc()
#>  107.                                             ├─tbl[!grepl("^Ensemble |^Pooled ", tbl$Estimate), , drop = FALSE]
#>  108.                                             ├─tibble:::`[.tbl_df`(...)
#>  109.                                             ├─base::grepl("^Ensemble |^Pooled ", tbl$Estimate)
#>  110.                                             │ └─base::is.factor(x)
#>  111.                                             ├─tbl$Estimate
#>  112.                                             └─tibble:::`$.tbl_df`(tbl, Estimate)
#> ── Warning ('test-rerun-regressions.R:176:7'): re-running Step 2 reuses its Results tab instead of adding another ──
#> Unknown or uninitialised column: `Estimate`.
#> Backtrace:
#>       ▆
#>    1. ├─shiny::testServer(...) at test-rerun-regressions.R:166:3
#>    2. │ ├─shiny:::withMockContext(...)
#>    3. │ │ ├─shiny::isolate(...)
#>    4. │ │ │ ├─shiny::..stacktraceoff..(...)
#>    5. │ │ │ └─ctx$run(...)
#>    6. │ │ │   ├─promises::with_promise_domain(...)
#>    7. │ │ │   │ └─domain$wrapSync(expr)
#>    8. │ │ │   ├─shiny::withReactiveDomain(...)
#>    9. │ │ │   │ └─promises::with_promise_domain(...)
#>   10. │ │ │   │   └─domain$wrapSync(expr)
#>   11. │ │ │   │     └─base::force(expr)
#>   12. │ │ │   ├─shiny:::with_otel_span_context(...)
#>   13. │ │ │   │ └─base::force(expr)
#>   14. │ │ │   ├─shiny::captureStackTraces(...)
#>   15. │ │ │   │ └─promises::with_promise_domain(...)
#>   16. │ │ │   │   └─domain$wrapSync(expr)
#>   17. │ │ │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   18. │ │ │   └─env$runWith(self, func)
#>   19. │ │ │     └─shiny (local) contextFunc()
#>   20. │ │ │       └─shiny::..stacktraceon..(expr)
#>   21. │ │ ├─shiny::withReactiveDomain(...)
#>   22. │ │ │ └─promises::with_promise_domain(...)
#>   23. │ │ │   └─domain$wrapSync(expr)
#>   24. │ │ │     └─base::force(expr)
#>   25. │ │ └─withr::with_options(...)
#>   26. │ │   └─base::force(code)
#>   27. │ └─rlang::eval_tidy(quosure, mask, rlang::caller_env())
#>   28. └─session$flushReact() at test-rerun-regressions.R:176:7
#>   29.   └─private$flush()
#>   30.     └─shiny:::flushReact()
#>   31.       └─.getReactiveEnvironment()$flush()
#>   32.         └─ctx$executeFlushCallbacks()
#>   33.           └─base::lapply(...)
#>   34.             └─shiny (local) FUN(X[[i]], ...)
#>   35.               └─shiny (local) flushCallback()
#>   36.                 ├─shiny:::hybrid_chain(...)
#>   37.                 │ └─shiny (local) do()
#>   38.                 │   ├─base::tryCatch(...)
#>   39.                 │   │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   40.                 │   │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   41.                 │   │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   42.                 │   ├─shiny::captureStackTraces(...)
#>   43.                 │   │ └─promises::with_promise_domain(...)
#>   44.                 │   │   └─domain$wrapSync(expr)
#>   45.                 │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   46.                 │   ├─base::withVisible(force(expr))
#>   47.                 │   └─base::force(expr)
#>   48.                 ├─shiny:::shinyCallingHandlers(run())
#>   49.                 │ ├─base::withCallingHandlers(...)
#>   50.                 │ └─shiny::captureStackTraces(expr)
#>   51.                 │   └─promises::with_promise_domain(...)
#>   52.                 │     └─domain$wrapSync(expr)
#>   53.                 │       └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   54.                 └─shiny (local) run()
#>   55.                   └─ctx$run(.func)
#>   56.                     ├─promises::with_promise_domain(...)
#>   57.                     │ └─domain$wrapSync(expr)
#>   58.                     ├─shiny::withReactiveDomain(...)
#>   59.                     │ └─promises::with_promise_domain(...)
#>   60.                     │   └─domain$wrapSync(expr)
#>   61.                     │     └─base::force(expr)
#>   62.                     ├─shiny:::with_otel_span_context(...)
#>   63.                     │ └─base::force(expr)
#>   64.                     ├─shiny::captureStackTraces(...)
#>   65.                     │ └─promises::with_promise_domain(...)
#>   66.                     │   └─domain$wrapSync(expr)
#>   67.                     │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   68.                     └─env$runWith(self, func)
#>   69.                       └─shiny (local) contextFunc()
#>   70.                         ├─shiny::..stacktraceon..(`<observer>`(...))
#>   71.                         └─shiny (local) `<observer>`(...)
#>   72.                           └─shiny::observe()
#>   73.                             ├─base::tryCatch(...)
#>   74.                             │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   75.                             │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   76.                             │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   77.                             ├─private$withCurrentOutput(name, func(self, name))
#>   78.                             │ └─promises::with_promise_domain(...)
#>   79.                             │   └─domain$wrapSync(expr)
#>   80.                             │     └─base::force(expr)
#>   81.                             └─shiny (local) func(self, name)
#>   82.                               ├─shiny::..stacktraceoff..(if (is.null(formals(renderFunc))) renderFunc() else renderFunc(...))
#>   83.                               └─DT (local) renderFunc(...)
#>   84.                                 ├─promises::with_promise_domain(domain, renderFunc())
#>   85.                                 │ └─domain$wrapSync(expr)
#>   86.                                 │   └─base::force(expr)
#>   87.                                 └─shiny (local) renderFunc()
#>   88.                                   ├─shiny::..stacktraceoff..(if (is.null(formals(renderFunc))) renderFunc() else renderFunc(...))
#>   89.                                   └─shiny (local) renderFunc(...)
#>   90.                                     ├─shiny:::hybrid_chain(...)
#>   91.                                     │ └─shiny (local) do()
#>   92.                                     │   ├─base::tryCatch(...)
#>   93.                                     │   │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   94.                                     │   │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   95.                                     │   │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   96.                                     │   ├─shiny::captureStackTraces(...)
#>   97.                                     │   │ └─promises::with_promise_domain(...)
#>   98.                                     │   │   └─domain$wrapSync(expr)
#>   99.                                     │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>  100.                                     │   ├─base::withVisible(force(expr))
#>  101.                                     │   └─base::force(expr)
#>  102.                                     ├─shiny::..stacktraceon..(func())
#>  103.                                     └─shiny (local) func()
#>  104.                                       └─DT (local) `::\nhtmlwidgets\nshinyRenderWidget`()
#>  105.                                         └─DT (local) widgetFunc()
#>  106.                                           └─wiseapp (local) exprFunc()
#>  107.                                             ├─tbl[!grepl("^Ensemble |^Pooled ", tbl$Estimate), , drop = FALSE]
#>  108.                                             ├─tibble:::`[.tbl_df`(...)
#>  109.                                             ├─base::grepl("^Ensemble |^Pooled ", tbl$Estimate)
#>  110.                                             │ └─base::is.factor(x)
#>  111.                                             ├─tbl$Estimate
#>  112.                                             └─tibble:::`$.tbl_df`(tbl, Estimate)
#> ── Warning ('test-rerun-regressions.R:204:33'): clearing Step 2 removes the tab so a later run re-adds it once ──
#> Unknown or uninitialised column: `Estimate`.
#> Backtrace:
#>       ▆
#>    1. ├─shiny::testServer(...) at test-rerun-regressions.R:197:3
#>    2. │ ├─shiny:::withMockContext(...)
#>    3. │ │ ├─shiny::isolate(...)
#>    4. │ │ │ ├─shiny::..stacktraceoff..(...)
#>    5. │ │ │ └─ctx$run(...)
#>    6. │ │ │   ├─promises::with_promise_domain(...)
#>    7. │ │ │   │ └─domain$wrapSync(expr)
#>    8. │ │ │   ├─shiny::withReactiveDomain(...)
#>    9. │ │ │   │ └─promises::with_promise_domain(...)
#>   10. │ │ │   │   └─domain$wrapSync(expr)
#>   11. │ │ │   │     └─base::force(expr)
#>   12. │ │ │   ├─shiny:::with_otel_span_context(...)
#>   13. │ │ │   │ └─base::force(expr)
#>   14. │ │ │   ├─shiny::captureStackTraces(...)
#>   15. │ │ │   │ └─promises::with_promise_domain(...)
#>   16. │ │ │   │   └─domain$wrapSync(expr)
#>   17. │ │ │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   18. │ │ │   └─env$runWith(self, func)
#>   19. │ │ │     └─shiny (local) contextFunc()
#>   20. │ │ │       └─shiny::..stacktraceon..(expr)
#>   21. │ │ ├─shiny::withReactiveDomain(...)
#>   22. │ │ │ └─promises::with_promise_domain(...)
#>   23. │ │ │   └─domain$wrapSync(expr)
#>   24. │ │ │     └─base::force(expr)
#>   25. │ │ └─withr::with_options(...)
#>   26. │ │   └─base::force(code)
#>   27. │ └─rlang::eval_tidy(quosure, mask, rlang::caller_env())
#>   28. └─session$flushReact() at test-rerun-regressions.R:204:33
#>   29.   └─private$flush()
#>   30.     └─shiny:::flushReact()
#>   31.       └─.getReactiveEnvironment()$flush()
#>   32.         └─ctx$executeFlushCallbacks()
#>   33.           └─base::lapply(...)
#>   34.             └─shiny (local) FUN(X[[i]], ...)
#>   35.               └─shiny (local) flushCallback()
#>   36.                 ├─shiny:::hybrid_chain(...)
#>   37.                 │ └─shiny (local) do()
#>   38.                 │   ├─base::tryCatch(...)
#>   39.                 │   │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   40.                 │   │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   41.                 │   │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   42.                 │   ├─shiny::captureStackTraces(...)
#>   43.                 │   │ └─promises::with_promise_domain(...)
#>   44.                 │   │   └─domain$wrapSync(expr)
#>   45.                 │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   46.                 │   ├─base::withVisible(force(expr))
#>   47.                 │   └─base::force(expr)
#>   48.                 ├─shiny:::shinyCallingHandlers(run())
#>   49.                 │ ├─base::withCallingHandlers(...)
#>   50.                 │ └─shiny::captureStackTraces(expr)
#>   51.                 │   └─promises::with_promise_domain(...)
#>   52.                 │     └─domain$wrapSync(expr)
#>   53.                 │       └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   54.                 └─shiny (local) run()
#>   55.                   └─ctx$run(.func)
#>   56.                     ├─promises::with_promise_domain(...)
#>   57.                     │ └─domain$wrapSync(expr)
#>   58.                     ├─shiny::withReactiveDomain(...)
#>   59.                     │ └─promises::with_promise_domain(...)
#>   60.                     │   └─domain$wrapSync(expr)
#>   61.                     │     └─base::force(expr)
#>   62.                     ├─shiny:::with_otel_span_context(...)
#>   63.                     │ └─base::force(expr)
#>   64.                     ├─shiny::captureStackTraces(...)
#>   65.                     │ └─promises::with_promise_domain(...)
#>   66.                     │   └─domain$wrapSync(expr)
#>   67.                     │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   68.                     └─env$runWith(self, func)
#>   69.                       └─shiny (local) contextFunc()
#>   70.                         ├─shiny::..stacktraceon..(`<observer>`(...))
#>   71.                         └─shiny (local) `<observer>`(...)
#>   72.                           └─shiny::observe()
#>   73.                             ├─base::tryCatch(...)
#>   74.                             │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   75.                             │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   76.                             │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   77.                             ├─private$withCurrentOutput(name, func(self, name))
#>   78.                             │ └─promises::with_promise_domain(...)
#>   79.                             │   └─domain$wrapSync(expr)
#>   80.                             │     └─base::force(expr)
#>   81.                             └─shiny (local) func(self, name)
#>   82.                               ├─shiny::..stacktraceoff..(if (is.null(formals(renderFunc))) renderFunc() else renderFunc(...))
#>   83.                               └─DT (local) renderFunc(...)
#>   84.                                 ├─promises::with_promise_domain(domain, renderFunc())
#>   85.                                 │ └─domain$wrapSync(expr)
#>   86.                                 │   └─base::force(expr)
#>   87.                                 └─shiny (local) renderFunc()
#>   88.                                   ├─shiny::..stacktraceoff..(if (is.null(formals(renderFunc))) renderFunc() else renderFunc(...))
#>   89.                                   └─shiny (local) renderFunc(...)
#>   90.                                     ├─shiny:::hybrid_chain(...)
#>   91.                                     │ └─shiny (local) do()
#>   92.                                     │   ├─base::tryCatch(...)
#>   93.                                     │   │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   94.                                     │   │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   95.                                     │   │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   96.                                     │   ├─shiny::captureStackTraces(...)
#>   97.                                     │   │ └─promises::with_promise_domain(...)
#>   98.                                     │   │   └─domain$wrapSync(expr)
#>   99.                                     │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>  100.                                     │   ├─base::withVisible(force(expr))
#>  101.                                     │   └─base::force(expr)
#>  102.                                     ├─shiny::..stacktraceon..(func())
#>  103.                                     └─shiny (local) func()
#>  104.                                       └─DT (local) `::\nhtmlwidgets\nshinyRenderWidget`()
#>  105.                                         └─DT (local) widgetFunc()
#>  106.                                           └─wiseapp (local) exprFunc()
#>  107.                                             ├─tbl[!grepl("^Ensemble |^Pooled ", tbl$Estimate), , drop = FALSE]
#>  108.                                             ├─tibble:::`[.tbl_df`(...)
#>  109.                                             ├─base::grepl("^Ensemble |^Pooled ", tbl$Estimate)
#>  110.                                             │ └─base::is.factor(x)
#>  111.                                             ├─tbl$Estimate
#>  112.                                             └─tibble:::`$.tbl_df`(tbl, Estimate)
#> ── Warning ('test-rerun-regressions.R:205:33'): clearing Step 2 removes the tab so a later run re-adds it once ──
#> Unknown or uninitialised column: `Estimate`.
#> Backtrace:
#>       ▆
#>    1. ├─shiny::testServer(...) at test-rerun-regressions.R:197:3
#>    2. │ ├─shiny:::withMockContext(...)
#>    3. │ │ ├─shiny::isolate(...)
#>    4. │ │ │ ├─shiny::..stacktraceoff..(...)
#>    5. │ │ │ └─ctx$run(...)
#>    6. │ │ │   ├─promises::with_promise_domain(...)
#>    7. │ │ │   │ └─domain$wrapSync(expr)
#>    8. │ │ │   ├─shiny::withReactiveDomain(...)
#>    9. │ │ │   │ └─promises::with_promise_domain(...)
#>   10. │ │ │   │   └─domain$wrapSync(expr)
#>   11. │ │ │   │     └─base::force(expr)
#>   12. │ │ │   ├─shiny:::with_otel_span_context(...)
#>   13. │ │ │   │ └─base::force(expr)
#>   14. │ │ │   ├─shiny::captureStackTraces(...)
#>   15. │ │ │   │ └─promises::with_promise_domain(...)
#>   16. │ │ │   │   └─domain$wrapSync(expr)
#>   17. │ │ │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   18. │ │ │   └─env$runWith(self, func)
#>   19. │ │ │     └─shiny (local) contextFunc()
#>   20. │ │ │       └─shiny::..stacktraceon..(expr)
#>   21. │ │ ├─shiny::withReactiveDomain(...)
#>   22. │ │ │ └─promises::with_promise_domain(...)
#>   23. │ │ │   └─domain$wrapSync(expr)
#>   24. │ │ │     └─base::force(expr)
#>   25. │ │ └─withr::with_options(...)
#>   26. │ │   └─base::force(code)
#>   27. │ └─rlang::eval_tidy(quosure, mask, rlang::caller_env())
#>   28. └─session$flushReact() at test-rerun-regressions.R:205:33
#>   29.   └─private$flush()
#>   30.     └─shiny:::flushReact()
#>   31.       └─.getReactiveEnvironment()$flush()
#>   32.         └─ctx$executeFlushCallbacks()
#>   33.           └─base::lapply(...)
#>   34.             └─shiny (local) FUN(X[[i]], ...)
#>   35.               └─shiny (local) flushCallback()
#>   36.                 ├─shiny:::hybrid_chain(...)
#>   37.                 │ └─shiny (local) do()
#>   38.                 │   ├─base::tryCatch(...)
#>   39.                 │   │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   40.                 │   │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   41.                 │   │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   42.                 │   ├─shiny::captureStackTraces(...)
#>   43.                 │   │ └─promises::with_promise_domain(...)
#>   44.                 │   │   └─domain$wrapSync(expr)
#>   45.                 │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   46.                 │   ├─base::withVisible(force(expr))
#>   47.                 │   └─base::force(expr)
#>   48.                 ├─shiny:::shinyCallingHandlers(run())
#>   49.                 │ ├─base::withCallingHandlers(...)
#>   50.                 │ └─shiny::captureStackTraces(expr)
#>   51.                 │   └─promises::with_promise_domain(...)
#>   52.                 │     └─domain$wrapSync(expr)
#>   53.                 │       └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   54.                 └─shiny (local) run()
#>   55.                   └─ctx$run(.func)
#>   56.                     ├─promises::with_promise_domain(...)
#>   57.                     │ └─domain$wrapSync(expr)
#>   58.                     ├─shiny::withReactiveDomain(...)
#>   59.                     │ └─promises::with_promise_domain(...)
#>   60.                     │   └─domain$wrapSync(expr)
#>   61.                     │     └─base::force(expr)
#>   62.                     ├─shiny:::with_otel_span_context(...)
#>   63.                     │ └─base::force(expr)
#>   64.                     ├─shiny::captureStackTraces(...)
#>   65.                     │ └─promises::with_promise_domain(...)
#>   66.                     │   └─domain$wrapSync(expr)
#>   67.                     │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   68.                     └─env$runWith(self, func)
#>   69.                       └─shiny (local) contextFunc()
#>   70.                         ├─shiny::..stacktraceon..(`<observer>`(...))
#>   71.                         └─shiny (local) `<observer>`(...)
#>   72.                           └─shiny::observe()
#>   73.                             ├─base::tryCatch(...)
#>   74.                             │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   75.                             │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   76.                             │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   77.                             ├─private$withCurrentOutput(name, func(self, name))
#>   78.                             │ └─promises::with_promise_domain(...)
#>   79.                             │   └─domain$wrapSync(expr)
#>   80.                             │     └─base::force(expr)
#>   81.                             └─shiny (local) func(self, name)
#>   82.                               ├─shiny::..stacktraceoff..(if (is.null(formals(renderFunc))) renderFunc() else renderFunc(...))
#>   83.                               └─DT (local) renderFunc(...)
#>   84.                                 ├─promises::with_promise_domain(domain, renderFunc())
#>   85.                                 │ └─domain$wrapSync(expr)
#>   86.                                 │   └─base::force(expr)
#>   87.                                 └─shiny (local) renderFunc()
#>   88.                                   ├─shiny::..stacktraceoff..(if (is.null(formals(renderFunc))) renderFunc() else renderFunc(...))
#>   89.                                   └─shiny (local) renderFunc(...)
#>   90.                                     ├─shiny:::hybrid_chain(...)
#>   91.                                     │ └─shiny (local) do()
#>   92.                                     │   ├─base::tryCatch(...)
#>   93.                                     │   │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   94.                                     │   │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   95.                                     │   │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   96.                                     │   ├─shiny::captureStackTraces(...)
#>   97.                                     │   │ └─promises::with_promise_domain(...)
#>   98.                                     │   │   └─domain$wrapSync(expr)
#>   99.                                     │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>  100.                                     │   ├─base::withVisible(force(expr))
#>  101.                                     │   └─base::force(expr)
#>  102.                                     ├─shiny::..stacktraceon..(func())
#>  103.                                     └─shiny (local) func()
#>  104.                                       └─DT (local) `::\nhtmlwidgets\nshinyRenderWidget`()
#>  105.                                         └─DT (local) widgetFunc()
#>  106.                                           └─wiseapp (local) exprFunc()
#>  107.                                             ├─tbl[!grepl("^Ensemble |^Pooled ", tbl$Estimate), , drop = FALSE]
#>  108.                                             ├─tibble:::`[.tbl_df`(...)
#>  109.                                             ├─base::grepl("^Ensemble |^Pooled ", tbl$Estimate)
#>  110.                                             │ └─base::is.factor(x)
#>  111.                                             ├─tbl$Estimate
#>  112.                                             └─tibble:::`$.tbl_df`(tbl, Estimate)
#> ── Warning ('test-rerun-regressions.R:214:33'): clearing Step 2 removes the tab so a later run re-adds it once ──
#> Unknown or uninitialised column: `Estimate`.
#> Backtrace:
#>       ▆
#>    1. ├─shiny::testServer(...) at test-rerun-regressions.R:197:3
#>    2. │ ├─shiny:::withMockContext(...)
#>    3. │ │ ├─shiny::isolate(...)
#>    4. │ │ │ ├─shiny::..stacktraceoff..(...)
#>    5. │ │ │ └─ctx$run(...)
#>    6. │ │ │   ├─promises::with_promise_domain(...)
#>    7. │ │ │   │ └─domain$wrapSync(expr)
#>    8. │ │ │   ├─shiny::withReactiveDomain(...)
#>    9. │ │ │   │ └─promises::with_promise_domain(...)
#>   10. │ │ │   │   └─domain$wrapSync(expr)
#>   11. │ │ │   │     └─base::force(expr)
#>   12. │ │ │   ├─shiny:::with_otel_span_context(...)
#>   13. │ │ │   │ └─base::force(expr)
#>   14. │ │ │   ├─shiny::captureStackTraces(...)
#>   15. │ │ │   │ └─promises::with_promise_domain(...)
#>   16. │ │ │   │   └─domain$wrapSync(expr)
#>   17. │ │ │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   18. │ │ │   └─env$runWith(self, func)
#>   19. │ │ │     └─shiny (local) contextFunc()
#>   20. │ │ │       └─shiny::..stacktraceon..(expr)
#>   21. │ │ ├─shiny::withReactiveDomain(...)
#>   22. │ │ │ └─promises::with_promise_domain(...)
#>   23. │ │ │   └─domain$wrapSync(expr)
#>   24. │ │ │     └─base::force(expr)
#>   25. │ │ └─withr::with_options(...)
#>   26. │ │   └─base::force(code)
#>   27. │ └─rlang::eval_tidy(quosure, mask, rlang::caller_env())
#>   28. └─session$flushReact() at test-rerun-regressions.R:214:33
#>   29.   └─private$flush()
#>   30.     └─shiny:::flushReact()
#>   31.       └─.getReactiveEnvironment()$flush()
#>   32.         └─ctx$executeFlushCallbacks()
#>   33.           └─base::lapply(...)
#>   34.             └─shiny (local) FUN(X[[i]], ...)
#>   35.               └─shiny (local) flushCallback()
#>   36.                 ├─shiny:::hybrid_chain(...)
#>   37.                 │ └─shiny (local) do()
#>   38.                 │   ├─base::tryCatch(...)
#>   39.                 │   │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   40.                 │   │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   41.                 │   │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   42.                 │   ├─shiny::captureStackTraces(...)
#>   43.                 │   │ └─promises::with_promise_domain(...)
#>   44.                 │   │   └─domain$wrapSync(expr)
#>   45.                 │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   46.                 │   ├─base::withVisible(force(expr))
#>   47.                 │   └─base::force(expr)
#>   48.                 ├─shiny:::shinyCallingHandlers(run())
#>   49.                 │ ├─base::withCallingHandlers(...)
#>   50.                 │ └─shiny::captureStackTraces(expr)
#>   51.                 │   └─promises::with_promise_domain(...)
#>   52.                 │     └─domain$wrapSync(expr)
#>   53.                 │       └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   54.                 └─shiny (local) run()
#>   55.                   └─ctx$run(.func)
#>   56.                     ├─promises::with_promise_domain(...)
#>   57.                     │ └─domain$wrapSync(expr)
#>   58.                     ├─shiny::withReactiveDomain(...)
#>   59.                     │ └─promises::with_promise_domain(...)
#>   60.                     │   └─domain$wrapSync(expr)
#>   61.                     │     └─base::force(expr)
#>   62.                     ├─shiny:::with_otel_span_context(...)
#>   63.                     │ └─base::force(expr)
#>   64.                     ├─shiny::captureStackTraces(...)
#>   65.                     │ └─promises::with_promise_domain(...)
#>   66.                     │   └─domain$wrapSync(expr)
#>   67.                     │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   68.                     └─env$runWith(self, func)
#>   69.                       └─shiny (local) contextFunc()
#>   70.                         ├─shiny::..stacktraceon..(`<observer>`(...))
#>   71.                         └─shiny (local) `<observer>`(...)
#>   72.                           └─shiny::observe()
#>   73.                             ├─base::tryCatch(...)
#>   74.                             │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   75.                             │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   76.                             │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   77.                             ├─private$withCurrentOutput(name, func(self, name))
#>   78.                             │ └─promises::with_promise_domain(...)
#>   79.                             │   └─domain$wrapSync(expr)
#>   80.                             │     └─base::force(expr)
#>   81.                             └─shiny (local) func(self, name)
#>   82.                               ├─shiny::..stacktraceoff..(if (is.null(formals(renderFunc))) renderFunc() else renderFunc(...))
#>   83.                               └─DT (local) renderFunc(...)
#>   84.                                 ├─promises::with_promise_domain(domain, renderFunc())
#>   85.                                 │ └─domain$wrapSync(expr)
#>   86.                                 │   └─base::force(expr)
#>   87.                                 └─shiny (local) renderFunc()
#>   88.                                   ├─shiny::..stacktraceoff..(if (is.null(formals(renderFunc))) renderFunc() else renderFunc(...))
#>   89.                                   └─shiny (local) renderFunc(...)
#>   90.                                     ├─shiny:::hybrid_chain(...)
#>   91.                                     │ └─shiny (local) do()
#>   92.                                     │   ├─base::tryCatch(...)
#>   93.                                     │   │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   94.                                     │   │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   95.                                     │   │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   96.                                     │   ├─shiny::captureStackTraces(...)
#>   97.                                     │   │ └─promises::with_promise_domain(...)
#>   98.                                     │   │   └─domain$wrapSync(expr)
#>   99.                                     │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>  100.                                     │   ├─base::withVisible(force(expr))
#>  101.                                     │   └─base::force(expr)
#>  102.                                     ├─shiny::..stacktraceon..(func())
#>  103.                                     └─shiny (local) func()
#>  104.                                       └─DT (local) `::\nhtmlwidgets\nshinyRenderWidget`()
#>  105.                                         └─DT (local) widgetFunc()
#>  106.                                           └─wiseapp (local) exprFunc()
#>  107.                                             ├─tbl[!grepl("^Ensemble |^Pooled ", tbl$Estimate), , drop = FALSE]
#>  108.                                             ├─tibble:::`[.tbl_df`(...)
#>  109.                                             ├─base::grepl("^Ensemble |^Pooled ", tbl$Estimate)
#>  110.                                             │ └─base::is.factor(x)
#>  111.                                             ├─tbl$Estimate
#>  112.                                             └─tibble:::`$.tbl_df`(tbl, Estimate)
#> ── Warning ('test-rerun-regressions.R:240:50'): re-running Step 2 refreshes the Results pane rather than stacking it ──
#> Unknown or uninitialised column: `Estimate`.
#> Backtrace:
#>       ▆
#>    1. ├─shiny::testServer(...) at test-rerun-regressions.R:233:3
#>    2. │ ├─shiny:::withMockContext(...)
#>    3. │ │ ├─shiny::isolate(...)
#>    4. │ │ │ ├─shiny::..stacktraceoff..(...)
#>    5. │ │ │ └─ctx$run(...)
#>    6. │ │ │   ├─promises::with_promise_domain(...)
#>    7. │ │ │   │ └─domain$wrapSync(expr)
#>    8. │ │ │   ├─shiny::withReactiveDomain(...)
#>    9. │ │ │   │ └─promises::with_promise_domain(...)
#>   10. │ │ │   │   └─domain$wrapSync(expr)
#>   11. │ │ │   │     └─base::force(expr)
#>   12. │ │ │   ├─shiny:::with_otel_span_context(...)
#>   13. │ │ │   │ └─base::force(expr)
#>   14. │ │ │   ├─shiny::captureStackTraces(...)
#>   15. │ │ │   │ └─promises::with_promise_domain(...)
#>   16. │ │ │   │   └─domain$wrapSync(expr)
#>   17. │ │ │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   18. │ │ │   └─env$runWith(self, func)
#>   19. │ │ │     └─shiny (local) contextFunc()
#>   20. │ │ │       └─shiny::..stacktraceon..(expr)
#>   21. │ │ ├─shiny::withReactiveDomain(...)
#>   22. │ │ │ └─promises::with_promise_domain(...)
#>   23. │ │ │   └─domain$wrapSync(expr)
#>   24. │ │ │     └─base::force(expr)
#>   25. │ │ └─withr::with_options(...)
#>   26. │ │   └─base::force(code)
#>   27. │ └─rlang::eval_tidy(quosure, mask, rlang::caller_env())
#>   28. └─session$flushReact() at test-rerun-regressions.R:240:50
#>   29.   └─private$flush()
#>   30.     └─shiny:::flushReact()
#>   31.       └─.getReactiveEnvironment()$flush()
#>   32.         └─ctx$executeFlushCallbacks()
#>   33.           └─base::lapply(...)
#>   34.             └─shiny (local) FUN(X[[i]], ...)
#>   35.               └─shiny (local) flushCallback()
#>   36.                 ├─shiny:::hybrid_chain(...)
#>   37.                 │ └─shiny (local) do()
#>   38.                 │   ├─base::tryCatch(...)
#>   39.                 │   │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   40.                 │   │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   41.                 │   │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   42.                 │   ├─shiny::captureStackTraces(...)
#>   43.                 │   │ └─promises::with_promise_domain(...)
#>   44.                 │   │   └─domain$wrapSync(expr)
#>   45.                 │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   46.                 │   ├─base::withVisible(force(expr))
#>   47.                 │   └─base::force(expr)
#>   48.                 ├─shiny:::shinyCallingHandlers(run())
#>   49.                 │ ├─base::withCallingHandlers(...)
#>   50.                 │ └─shiny::captureStackTraces(expr)
#>   51.                 │   └─promises::with_promise_domain(...)
#>   52.                 │     └─domain$wrapSync(expr)
#>   53.                 │       └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   54.                 └─shiny (local) run()
#>   55.                   └─ctx$run(.func)
#>   56.                     ├─promises::with_promise_domain(...)
#>   57.                     │ └─domain$wrapSync(expr)
#>   58.                     ├─shiny::withReactiveDomain(...)
#>   59.                     │ └─promises::with_promise_domain(...)
#>   60.                     │   └─domain$wrapSync(expr)
#>   61.                     │     └─base::force(expr)
#>   62.                     ├─shiny:::with_otel_span_context(...)
#>   63.                     │ └─base::force(expr)
#>   64.                     ├─shiny::captureStackTraces(...)
#>   65.                     │ └─promises::with_promise_domain(...)
#>   66.                     │   └─domain$wrapSync(expr)
#>   67.                     │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   68.                     └─env$runWith(self, func)
#>   69.                       └─shiny (local) contextFunc()
#>   70.                         ├─shiny::..stacktraceon..(`<observer>`(...))
#>   71.                         └─shiny (local) `<observer>`(...)
#>   72.                           └─shiny::observe()
#>   73.                             ├─base::tryCatch(...)
#>   74.                             │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   75.                             │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   76.                             │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   77.                             ├─private$withCurrentOutput(name, func(self, name))
#>   78.                             │ └─promises::with_promise_domain(...)
#>   79.                             │   └─domain$wrapSync(expr)
#>   80.                             │     └─base::force(expr)
#>   81.                             └─shiny (local) func(self, name)
#>   82.                               ├─shiny::..stacktraceoff..(if (is.null(formals(renderFunc))) renderFunc() else renderFunc(...))
#>   83.                               └─DT (local) renderFunc(...)
#>   84.                                 ├─promises::with_promise_domain(domain, renderFunc())
#>   85.                                 │ └─domain$wrapSync(expr)
#>   86.                                 │   └─base::force(expr)
#>   87.                                 └─shiny (local) renderFunc()
#>   88.                                   ├─shiny::..stacktraceoff..(if (is.null(formals(renderFunc))) renderFunc() else renderFunc(...))
#>   89.                                   └─shiny (local) renderFunc(...)
#>   90.                                     ├─shiny:::hybrid_chain(...)
#>   91.                                     │ └─shiny (local) do()
#>   92.                                     │   ├─base::tryCatch(...)
#>   93.                                     │   │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   94.                                     │   │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   95.                                     │   │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   96.                                     │   ├─shiny::captureStackTraces(...)
#>   97.                                     │   │ └─promises::with_promise_domain(...)
#>   98.                                     │   │   └─domain$wrapSync(expr)
#>   99.                                     │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>  100.                                     │   ├─base::withVisible(force(expr))
#>  101.                                     │   └─base::force(expr)
#>  102.                                     ├─shiny::..stacktraceon..(func())
#>  103.                                     └─shiny (local) func()
#>  104.                                       └─DT (local) `::\nhtmlwidgets\nshinyRenderWidget`()
#>  105.                                         └─DT (local) widgetFunc()
#>  106.                                           └─wiseapp (local) exprFunc()
#>  107.                                             ├─tbl[!grepl("^Ensemble |^Pooled ", tbl$Estimate), , drop = FALSE]
#>  108.                                             ├─tibble:::`[.tbl_df`(...)
#>  109.                                             ├─base::grepl("^Ensemble |^Pooled ", tbl$Estimate)
#>  110.                                             │ └─base::is.factor(x)
#>  111.                                             ├─tbl$Estimate
#>  112.                                             └─tibble:::`$.tbl_df`(tbl, Estimate)
#> ── Warning ('test-rerun-regressions.R:240:50'): re-running Step 2 refreshes the Results pane rather than stacking it ──
#> Unknown or uninitialised column: `Estimate`.
#> Backtrace:
#>       ▆
#>    1. ├─shiny::testServer(...) at test-rerun-regressions.R:233:3
#>    2. │ ├─shiny:::withMockContext(...)
#>    3. │ │ ├─shiny::isolate(...)
#>    4. │ │ │ ├─shiny::..stacktraceoff..(...)
#>    5. │ │ │ └─ctx$run(...)
#>    6. │ │ │   ├─promises::with_promise_domain(...)
#>    7. │ │ │   │ └─domain$wrapSync(expr)
#>    8. │ │ │   ├─shiny::withReactiveDomain(...)
#>    9. │ │ │   │ └─promises::with_promise_domain(...)
#>   10. │ │ │   │   └─domain$wrapSync(expr)
#>   11. │ │ │   │     └─base::force(expr)
#>   12. │ │ │   ├─shiny:::with_otel_span_context(...)
#>   13. │ │ │   │ └─base::force(expr)
#>   14. │ │ │   ├─shiny::captureStackTraces(...)
#>   15. │ │ │   │ └─promises::with_promise_domain(...)
#>   16. │ │ │   │   └─domain$wrapSync(expr)
#>   17. │ │ │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   18. │ │ │   └─env$runWith(self, func)
#>   19. │ │ │     └─shiny (local) contextFunc()
#>   20. │ │ │       └─shiny::..stacktraceon..(expr)
#>   21. │ │ ├─shiny::withReactiveDomain(...)
#>   22. │ │ │ └─promises::with_promise_domain(...)
#>   23. │ │ │   └─domain$wrapSync(expr)
#>   24. │ │ │     └─base::force(expr)
#>   25. │ │ └─withr::with_options(...)
#>   26. │ │   └─base::force(code)
#>   27. │ └─rlang::eval_tidy(quosure, mask, rlang::caller_env())
#>   28. └─session$flushReact() at test-rerun-regressions.R:240:50
#>   29.   └─private$flush()
#>   30.     └─shiny:::flushReact()
#>   31.       └─.getReactiveEnvironment()$flush()
#>   32.         └─ctx$executeFlushCallbacks()
#>   33.           └─base::lapply(...)
#>   34.             └─shiny (local) FUN(X[[i]], ...)
#>   35.               └─shiny (local) flushCallback()
#>   36.                 ├─shiny:::hybrid_chain(...)
#>   37.                 │ └─shiny (local) do()
#>   38.                 │   ├─base::tryCatch(...)
#>   39.                 │   │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   40.                 │   │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   41.                 │   │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   42.                 │   ├─shiny::captureStackTraces(...)
#>   43.                 │   │ └─promises::with_promise_domain(...)
#>   44.                 │   │   └─domain$wrapSync(expr)
#>   45.                 │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   46.                 │   ├─base::withVisible(force(expr))
#>   47.                 │   └─base::force(expr)
#>   48.                 ├─shiny:::shinyCallingHandlers(run())
#>   49.                 │ ├─base::withCallingHandlers(...)
#>   50.                 │ └─shiny::captureStackTraces(expr)
#>   51.                 │   └─promises::with_promise_domain(...)
#>   52.                 │     └─domain$wrapSync(expr)
#>   53.                 │       └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   54.                 └─shiny (local) run()
#>   55.                   └─ctx$run(.func)
#>   56.                     ├─promises::with_promise_domain(...)
#>   57.                     │ └─domain$wrapSync(expr)
#>   58.                     ├─shiny::withReactiveDomain(...)
#>   59.                     │ └─promises::with_promise_domain(...)
#>   60.                     │   └─domain$wrapSync(expr)
#>   61.                     │     └─base::force(expr)
#>   62.                     ├─shiny:::with_otel_span_context(...)
#>   63.                     │ └─base::force(expr)
#>   64.                     ├─shiny::captureStackTraces(...)
#>   65.                     │ └─promises::with_promise_domain(...)
#>   66.                     │   └─domain$wrapSync(expr)
#>   67.                     │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   68.                     └─env$runWith(self, func)
#>   69.                       └─shiny (local) contextFunc()
#>   70.                         ├─shiny::..stacktraceon..(`<observer>`(...))
#>   71.                         └─shiny (local) `<observer>`(...)
#>   72.                           └─shiny::observe()
#>   73.                             ├─base::tryCatch(...)
#>   74.                             │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   75.                             │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   76.                             │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   77.                             ├─private$withCurrentOutput(name, func(self, name))
#>   78.                             │ └─promises::with_promise_domain(...)
#>   79.                             │   └─domain$wrapSync(expr)
#>   80.                             │     └─base::force(expr)
#>   81.                             └─shiny (local) func(self, name)
#>   82.                               ├─shiny::..stacktraceoff..(if (is.null(formals(renderFunc))) renderFunc() else renderFunc(...))
#>   83.                               └─DT (local) renderFunc(...)
#>   84.                                 ├─promises::with_promise_domain(domain, renderFunc())
#>   85.                                 │ └─domain$wrapSync(expr)
#>   86.                                 │   └─base::force(expr)
#>   87.                                 └─shiny (local) renderFunc()
#>   88.                                   ├─shiny::..stacktraceoff..(if (is.null(formals(renderFunc))) renderFunc() else renderFunc(...))
#>   89.                                   └─shiny (local) renderFunc(...)
#>   90.                                     ├─shiny:::hybrid_chain(...)
#>   91.                                     │ └─shiny (local) do()
#>   92.                                     │   ├─base::tryCatch(...)
#>   93.                                     │   │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   94.                                     │   │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   95.                                     │   │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   96.                                     │   ├─shiny::captureStackTraces(...)
#>   97.                                     │   │ └─promises::with_promise_domain(...)
#>   98.                                     │   │   └─domain$wrapSync(expr)
#>   99.                                     │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>  100.                                     │   ├─base::withVisible(force(expr))
#>  101.                                     │   └─base::force(expr)
#>  102.                                     ├─shiny::..stacktraceon..(func())
#>  103.                                     └─shiny (local) func()
#>  104.                                       └─DT (local) `::\nhtmlwidgets\nshinyRenderWidget`()
#>  105.                                         └─DT (local) widgetFunc()
#>  106.                                           └─wiseapp (local) exprFunc()
#>  107.                                             ├─tbl[!grepl("^Ensemble |^Pooled ", tbl$Estimate), , drop = FALSE]
#>  108.                                             ├─tibble:::`[.tbl_df`(...)
#>  109.                                             ├─base::grepl("^Ensemble |^Pooled ", tbl$Estimate)
#>  110.                                             │ └─base::is.factor(x)
#>  111.                                             ├─tbl$Estimate
#>  112.                                             └─tibble:::`$.tbl_df`(tbl, Estimate)
#> ── Warning ('test-rerun-regressions.R:240:50'): re-running Step 2 refreshes the Results pane rather than stacking it ──
#> Unknown or uninitialised column: `Estimate`.
#> Backtrace:
#>       ▆
#>    1. ├─shiny::testServer(...) at test-rerun-regressions.R:233:3
#>    2. │ ├─shiny:::withMockContext(...)
#>    3. │ │ ├─shiny::isolate(...)
#>    4. │ │ │ ├─shiny::..stacktraceoff..(...)
#>    5. │ │ │ └─ctx$run(...)
#>    6. │ │ │   ├─promises::with_promise_domain(...)
#>    7. │ │ │   │ └─domain$wrapSync(expr)
#>    8. │ │ │   ├─shiny::withReactiveDomain(...)
#>    9. │ │ │   │ └─promises::with_promise_domain(...)
#>   10. │ │ │   │   └─domain$wrapSync(expr)
#>   11. │ │ │   │     └─base::force(expr)
#>   12. │ │ │   ├─shiny:::with_otel_span_context(...)
#>   13. │ │ │   │ └─base::force(expr)
#>   14. │ │ │   ├─shiny::captureStackTraces(...)
#>   15. │ │ │   │ └─promises::with_promise_domain(...)
#>   16. │ │ │   │   └─domain$wrapSync(expr)
#>   17. │ │ │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   18. │ │ │   └─env$runWith(self, func)
#>   19. │ │ │     └─shiny (local) contextFunc()
#>   20. │ │ │       └─shiny::..stacktraceon..(expr)
#>   21. │ │ ├─shiny::withReactiveDomain(...)
#>   22. │ │ │ └─promises::with_promise_domain(...)
#>   23. │ │ │   └─domain$wrapSync(expr)
#>   24. │ │ │     └─base::force(expr)
#>   25. │ │ └─withr::with_options(...)
#>   26. │ │   └─base::force(code)
#>   27. │ └─rlang::eval_tidy(quosure, mask, rlang::caller_env())
#>   28. └─session$flushReact() at test-rerun-regressions.R:240:50
#>   29.   └─private$flush()
#>   30.     └─shiny:::flushReact()
#>   31.       └─.getReactiveEnvironment()$flush()
#>   32.         └─ctx$executeFlushCallbacks()
#>   33.           └─base::lapply(...)
#>   34.             └─shiny (local) FUN(X[[i]], ...)
#>   35.               └─shiny (local) flushCallback()
#>   36.                 ├─shiny:::hybrid_chain(...)
#>   37.                 │ └─shiny (local) do()
#>   38.                 │   ├─base::tryCatch(...)
#>   39.                 │   │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   40.                 │   │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   41.                 │   │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   42.                 │   ├─shiny::captureStackTraces(...)
#>   43.                 │   │ └─promises::with_promise_domain(...)
#>   44.                 │   │   └─domain$wrapSync(expr)
#>   45.                 │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   46.                 │   ├─base::withVisible(force(expr))
#>   47.                 │   └─base::force(expr)
#>   48.                 ├─shiny:::shinyCallingHandlers(run())
#>   49.                 │ ├─base::withCallingHandlers(...)
#>   50.                 │ └─shiny::captureStackTraces(expr)
#>   51.                 │   └─promises::with_promise_domain(...)
#>   52.                 │     └─domain$wrapSync(expr)
#>   53.                 │       └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   54.                 └─shiny (local) run()
#>   55.                   └─ctx$run(.func)
#>   56.                     ├─promises::with_promise_domain(...)
#>   57.                     │ └─domain$wrapSync(expr)
#>   58.                     ├─shiny::withReactiveDomain(...)
#>   59.                     │ └─promises::with_promise_domain(...)
#>   60.                     │   └─domain$wrapSync(expr)
#>   61.                     │     └─base::force(expr)
#>   62.                     ├─shiny:::with_otel_span_context(...)
#>   63.                     │ └─base::force(expr)
#>   64.                     ├─shiny::captureStackTraces(...)
#>   65.                     │ └─promises::with_promise_domain(...)
#>   66.                     │   └─domain$wrapSync(expr)
#>   67.                     │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>   68.                     └─env$runWith(self, func)
#>   69.                       └─shiny (local) contextFunc()
#>   70.                         ├─shiny::..stacktraceon..(`<observer>`(...))
#>   71.                         └─shiny (local) `<observer>`(...)
#>   72.                           └─shiny::observe()
#>   73.                             ├─base::tryCatch(...)
#>   74.                             │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   75.                             │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   76.                             │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   77.                             ├─private$withCurrentOutput(name, func(self, name))
#>   78.                             │ └─promises::with_promise_domain(...)
#>   79.                             │   └─domain$wrapSync(expr)
#>   80.                             │     └─base::force(expr)
#>   81.                             └─shiny (local) func(self, name)
#>   82.                               ├─shiny::..stacktraceoff..(if (is.null(formals(renderFunc))) renderFunc() else renderFunc(...))
#>   83.                               └─DT (local) renderFunc(...)
#>   84.                                 ├─promises::with_promise_domain(domain, renderFunc())
#>   85.                                 │ └─domain$wrapSync(expr)
#>   86.                                 │   └─base::force(expr)
#>   87.                                 └─shiny (local) renderFunc()
#>   88.                                   ├─shiny::..stacktraceoff..(if (is.null(formals(renderFunc))) renderFunc() else renderFunc(...))
#>   89.                                   └─shiny (local) renderFunc(...)
#>   90.                                     ├─shiny:::hybrid_chain(...)
#>   91.                                     │ └─shiny (local) do()
#>   92.                                     │   ├─base::tryCatch(...)
#>   93.                                     │   │ └─base (local) tryCatchList(expr, classes, parentenv, handlers)
#>   94.                                     │   │   └─base (local) tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>   95.                                     │   │     └─base (local) doTryCatch(return(expr), name, parentenv, handler)
#>   96.                                     │   ├─shiny::captureStackTraces(...)
#>   97.                                     │   │ └─promises::with_promise_domain(...)
#>   98.                                     │   │   └─domain$wrapSync(expr)
#>   99.                                     │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>  100.                                     │   ├─base::withVisible(force(expr))
#>  101.                                     │   └─base::force(expr)
#>  102.                                     ├─shiny::..stacktraceon..(func())
#>  103.                                     └─shiny (local) func()
#>  104.                                       └─DT (local) `::\nhtmlwidgets\nshinyRenderWidget`()
#>  105.                                         └─DT (local) widgetFunc()
#>  106.                                           └─wiseapp (local) exprFunc()
#>  107.                                             ├─tbl[!grepl("^Ensemble |^Pooled ", tbl$Estimate), , drop = FALSE]
#>  108.                                             ├─tibble:::`[.tbl_df`(...)
#>  109.                                             ├─base::grepl("^Ensemble |^Pooled ", tbl$Estimate)
#>  110.                                             │ └─base::is.factor(x)
#>  111.                                             ├─tbl$Estimate
#>  112.                                             └─tibble:::`$.tbl_df`(tbl, Estimate)
#> 
#> ══ Failed tests ════════════════════════════════════════════════════════════════
#> ── Error ('test-determinism.R:232:3'): parallel MICE Lasso is deterministic and restores caller RNG ──
#> <packageNotFoundError/error/condition>
#> Error in `loadNamespace(x)`: there is no package called 'furrr'
#> Backtrace:
#>     ▆
#>  1. ├─base::do.call(run_lasso_selection, args) at test-determinism.R:232:3
#>  2. ├─wiseapp (local) `<fn>`(...)
#>  3. │ ├─withr::with_seed(...)
#>  4. │ │ └─withr::with_preserve_seed(...)
#>  5. │ └─mice::futuremice(...)
#>  6. └─base::loadNamespace(x)
#>  7.   └─base::withRestarts(stop(cond), retry_loadNamespace = function() NULL)
#>  8.     └─base (local) withOneRestart(expr, restarts[[1L]])
#>  9.       └─base (local) doWithOneRestart(return(expr), restart)
#> ── Failure ('test-export-bundle.R:416:5'): a deferred setting is applied once its control appears (UI-52) ──
#> Expected `"late_ctrl" %in% ls(sent)` to be FALSE.
#> Differences:
#> `actual`:   TRUE 
#> `expected`: FALSE
#> 
#> Backtrace:
#>      ▆
#>   1. ├─shiny::testServer(...) at test-export-bundle.R:400:3
#>   2. │ ├─shiny:::withMockContext(...)
#>   3. │ │ ├─shiny::isolate(...)
#>   4. │ │ │ ├─shiny::..stacktraceoff..(...)
#>   5. │ │ │ └─ctx$run(...)
#>   6. │ │ │   ├─promises::with_promise_domain(...)
#>   7. │ │ │   │ └─domain$wrapSync(expr)
#>   8. │ │ │   ├─shiny::withReactiveDomain(...)
#>   9. │ │ │   │ └─promises::with_promise_domain(...)
#>  10. │ │ │   │   └─domain$wrapSync(expr)
#>  11. │ │ │   │     └─base::force(expr)
#>  12. │ │ │   ├─shiny:::with_otel_span_context(...)
#>  13. │ │ │   │ └─base::force(expr)
#>  14. │ │ │   ├─shiny::captureStackTraces(...)
#>  15. │ │ │   │ └─promises::with_promise_domain(...)
#>  16. │ │ │   │   └─domain$wrapSync(expr)
#>  17. │ │ │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>  18. │ │ │   └─env$runWith(self, func)
#>  19. │ │ │     └─shiny (local) contextFunc()
#>  20. │ │ │       └─shiny::..stacktraceon..(expr)
#>  21. │ │ ├─shiny::withReactiveDomain(...)
#>  22. │ │ │ └─promises::with_promise_domain(...)
#>  23. │ │ │   └─domain$wrapSync(expr)
#>  24. │ │ │     └─base::force(expr)
#>  25. │ │ └─withr::with_options(...)
#>  26. │ │   └─base::force(code)
#>  27. │ └─rlang::eval_tidy(quosure, mask, rlang::caller_env())
#>  28. └─testthat::expect_false("late_ctrl" %in% ls(sent)) at test-export-bundle.R:416:5
#> ── Failure ('test-export-bundle.R:435:5'): the heartbeat applies deferred settings without any input change ──
#> Expected `"late_ctrl" %in% ls(sent)` to be FALSE.
#> Differences:
#> `actual`:   TRUE 
#> `expected`: FALSE
#> 
#> Backtrace:
#>      ▆
#>   1. ├─shiny::testServer(...) at test-export-bundle.R:427:3
#>   2. │ ├─shiny:::withMockContext(...)
#>   3. │ │ ├─shiny::isolate(...)
#>   4. │ │ │ ├─shiny::..stacktraceoff..(...)
#>   5. │ │ │ └─ctx$run(...)
#>   6. │ │ │   ├─promises::with_promise_domain(...)
#>   7. │ │ │   │ └─domain$wrapSync(expr)
#>   8. │ │ │   ├─shiny::withReactiveDomain(...)
#>   9. │ │ │   │ └─promises::with_promise_domain(...)
#>  10. │ │ │   │   └─domain$wrapSync(expr)
#>  11. │ │ │   │     └─base::force(expr)
#>  12. │ │ │   ├─shiny:::with_otel_span_context(...)
#>  13. │ │ │   │ └─base::force(expr)
#>  14. │ │ │   ├─shiny::captureStackTraces(...)
#>  15. │ │ │   │ └─promises::with_promise_domain(...)
#>  16. │ │ │   │   └─domain$wrapSync(expr)
#>  17. │ │ │   │     └─base::withCallingHandlers(expr, error = doCaptureStack)
#>  18. │ │ │   └─env$runWith(self, func)
#>  19. │ │ │     └─shiny (local) contextFunc()
#>  20. │ │ │       └─shiny::..stacktraceon..(expr)
#>  21. │ │ ├─shiny::withReactiveDomain(...)
#>  22. │ │ │ └─promises::with_promise_domain(...)
#>  23. │ │ │   └─domain$wrapSync(expr)
#>  24. │ │ │     └─base::force(expr)
#>  25. │ │ └─withr::with_options(...)
#>  26. │ │   └─base::force(code)
#>  27. │ └─rlang::eval_tidy(quosure, mask, rlang::caller_env())
#>  28. └─testthat::expect_false("late_ctrl" %in% ls(sent)) at test-export-bundle.R:435:5
#> 
#> [ FAIL 3 | WARN 10 | SKIP 22 | PASS 1414 ]
#> Error:
#> ! Test failures.
#> Execution halted
#> 
#> 1 error ✖ | 1 warning ✖ | 4 notes ✖
#> Error:
#> ! R CMD check found ERRORs
```

``` r
covr::package_coverage()
#> Error:
#> ! Failure in `/private/var/folders/ft/lf7dynfs0d5_pntggyshz0r40000gq/T/RtmpMNygss/R_LIBS13f0832c1dc46/wiseapp/wiseapp-tests/testthat.Rout.fail`
#> estthat::expect_false("late_ctrl" %in% ls(sent)) at test-export-bundle.R:435:5
#> 
#> [ FAIL 2 | WARN 10 | SKIP 0 | PASS 1473 ]
#> Error:
#> ! Test failures.
#> Execution halted
```
