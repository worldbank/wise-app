library(testthat)

test_that("the decomposition owner marker is compared by value, not identity", {
  copy <- unserialize(serialize(.decomposition_context_owner, NULL))
  expect_false(identical(copy, .decomposition_context_owner))
  expect_true(.is_decomposition_context_owner(copy))
  expect_true(.is_decomposition_context_owner(.decomposition_context_owner))
  expect_false(.is_decomposition_context_owner(new.env()))
  expect_false(.is_decomposition_context_owner(NULL))
})

test_that("step3_baseline_arm keeps the Step 2 signature and residual treatment", {
  hs <- list(.sig = list(a = 1), residuals = NULL, pipeline = "p")
  out <- step3_baseline_arm(hs, "normal")
  expect_identical(out$residuals, "normal")
  expect_identical(out$.step2_sig, list(a = 1))
  expect_identical(out$pipeline, "p")
  expect_identical(step3_baseline_arm(list(residuals = "none"), "normal")$residuals, "none")
})

test_that("worker eligibility needs a matching on-disk Step 2 artifact", {
  f <- withr::local_tempfile(fileext = ".qs2")
  writeLines("x", f)
  ss <- list(a = 1, b = 2)
  hs <- list(.artifact = list(file = f, sig = "s", scenario_names = c("a", "b")))
  expect_true(.wise_step3_async_artifact_ok(hs, ss))
  expect_false(.wise_step3_async_artifact_ok(list(), ss))
  expect_false(.wise_step3_async_artifact_ok(hs, list(a = 1)))
  unlink(f)
  expect_false(.wise_step3_async_artifact_ok(hs, ss))
})

test_that("an adopted Step 2 result file is moved out of the job directory", {
  root <- withr::local_tempdir()
  withr::local_envvar(WISEAPP_ASYNC_ARTIFACT_ROOT = root)
  job_dir <- file.path(root, "job-1")
  dir.create(job_dir)
  writeLines("result", file.path(job_dir, "result.qs2"))
  kept <- .wise_step2_async_retain_result(
    list(id = "job-1", artifact_dir = job_dir), result_sig = "sig"
  )
  expect_true(file.exists(kept$file))
  expect_false(file.exists(file.path(job_dir, "result.qs2")))
  expect_identical(kept$sig, "sig")
  expect_null(.wise_step2_async_retain_result(
    list(id = "job-2", artifact_dir = job_dir), result_sig = "sig"
  ))
})

test_that("worker run validation refuses unlocked or mismatched runs", {
  ctx <- list2env(list(
    context_version = 2L, context_owner = .decomposition_context_owner,
    run_identity = "r1"
  ), parent = emptyenv())
  lockEnvironment(ctx, bindings = TRUE)
  channels <- list2env(
    list(status = "ok", context = ctx, run_identity = "r1"), parent = emptyenv()
  )
  expect_error(
    step3_validate_worker_run(list(
      pol_out = list(annual_channels = channels), decomp_context = ctx
    )),
    "no valid annual channels"
  )
  lockEnvironment(channels, bindings = TRUE)
  expect_true(step3_validate_worker_run(list(
    pol_out = list(annual_channels = channels), decomp_context = ctx
  )))
  other <- list2env(as.list(ctx), parent = emptyenv())
  lockEnvironment(other, bindings = TRUE)
  expect_error(
    step3_validate_worker_run(list(
      pol_out = list(annual_channels = channels), decomp_context = other
    )),
    "differ"
  )
})

# dev/ is not part of the built package, so the fixture parity test only runs
# in a source checkout.
test_that("a worker run equals the in-process run on the smoke fixture", {
  skip_if_not(file.exists(testthat::test_path("../../dev/bench_step3_helpers.R")),
    "dev/ benchmark helpers not available")
  skip_if_not_installed("qs2")
  source(testthat::test_path("../../dev/bench_step3_helpers.R"), local = TRUE)
  source(testthat::test_path("../../dev/bench_step2_helpers.R"), local = TRUE)

  input <- .bench_small_step3_input(n = 60L)
  baseline <- .bench_small_step2_result(input, "ols", "one_ssp_one_period")
  fixture <- .bench_step3_policy_fixtures("targeted_sp")[[1L]]
  mf <- input$models[["ols"]]
  hs <- baseline$hist_sim_result
  hs$.sig <- list(step = "step2-fixture")
  ss <- baseline$new_scenarios %||% list()
  args <- list(
    svy = input$svy, hs = hs, ss = ss, mf = mf,
    sp_cfg = fixture$sp, infra_cfg = fixture$infra,
    model_vars = .bench_step3_model_terms(mf),
    analysis_unit = "hh", skip_coef = TRUE, residuals = "original",
    run_generation = 1L, seed = 123L
  )
  direct <- do.call(step3_compute, args)

  # Write the Step 2 artifact the way the Step 2 worker does, then run the
  # Step 3 worker body on it.
  dir <- withr::local_tempdir()
  art <- file.path(dir, "step2.qs2")
  step2 <- list(
    hist_sim_result = hs, new_scenarios = ss, .sig = "step2-result-sig"
  )
  qs2::qs_save(step2_share_constants(step2), art)
  snapshot <- c(
    args[setdiff(names(args), c("hs", "ss"))],
    list(
      artifact = list(file = art, sig = "step2-result-sig"),
      hs_overlay = hs[intersect(c("hist_label", "sim_summary", ".sig"), names(hs))]
    )
  )
  manifest <- step3_async_worker(snapshot, file.path(dir, "step3"))
  worker <- step3_read_worker_result(
    manifest, file.path(dir, "step3"), hs, ss, "original"
  )

  expect_identical(worker$pol_out$hist_sim, direct$pol_out$hist_sim)
  expect_identical(worker$pol_out$saved_scenarios, direct$pol_out$saved_scenarios)
  expect_identical(worker$pol_out$decomp_scenarios, direct$pol_out$decomp_scenarios)
  expect_identical(worker$diagnostic_summary, direct$diagnostic_summary)
  expect_identical(worker$svy_mod, direct$svy_mod)
  expect_identical(worker$no_effect, direct$no_effect)
  expect_identical(worker$baseline_out, direct$baseline_out)
  expect_true(environmentIsLocked(worker$pol_out$annual_channels))

  # The deserialised run still drives the metric decomposition.
  decompose <- function(run) {
    .policy_metric_decomposition(
      baseline_hist = run$baseline_out, policy_hist = run$pol_out$hist_sim,
      baseline_scenarios = run$baseline_scenarios_out,
      policy_scenarios = run$pol_out$saved_scenarios %||% list(),
      prepared = run$pol_out$annual_channels, method = "mean",
      requested_residuals = "original", analysis_unit = "hh",
      validation_cache = new.env(parent = emptyenv())
    )
  }
  expect_identical(decompose(worker)$status, "ok")
  expect_identical(decompose(worker)$summary, decompose(direct)$summary)
})

test_that("a stale Step 2 artifact is refused by the worker", {
  skip_if_not_installed("qs2")
  dir <- withr::local_tempdir()
  art <- file.path(dir, "step2.qs2")
  qs2::qs_save(step2_share_constants(list(
    hist_sim_result = list(), new_scenarios = list(), .sig = "other"
  )), art)
  expect_error(
    step3_async_worker(
      list(artifact = list(file = art, sig = "expected"), hs_overlay = list()),
      file.path(dir, "step3")
    ),
    "does not match"
  )
})

test_that("a run submitted to the shared daemon is read back and equals the in-process run", {
  skip_on_cran()
  skip_if_not(file.exists(testthat::test_path("../../dev/bench_step3_helpers.R")),
    "dev/ benchmark helpers not available")
  skip_if_not_installed("qs2")
  source(testthat::test_path("../../dev/bench_step3_helpers.R"), local = TRUE)
  source(testthat::test_path("../../dev/bench_step2_helpers.R"), local = TRUE)

  state <- .wise_step2_async_state
  withr::local_envvar(WISEAPP_ASYNC_SYNC = "0")
  try(mirai::daemons(0L), silent = TRUE)
  state$started <- FALSE
  withr::defer({
    try(mirai::daemons(0L), silent = TRUE)
    state$started <- FALSE
  })
  root <- withr::local_tempdir()
  withr::local_envvar(WISEAPP_ASYNC_ARTIFACT_ROOT = root)

  input <- .bench_small_step3_input(n = 60L)
  baseline <- .bench_small_step2_result(input, "ols", "one_ssp_one_period")
  fixture <- .bench_step3_policy_fixtures("targeted_sp")[[1L]]
  mf <- input$models[["ols"]]
  hs <- baseline$hist_sim_result
  hs$.sig <- list(step = "step2-fixture")
  ss <- baseline$new_scenarios %||% list()
  args <- list(
    svy = input$svy, mf = mf, sp_cfg = fixture$sp, infra_cfg = fixture$infra,
    model_vars = .bench_step3_model_terms(mf), analysis_unit = "hh",
    skip_coef = TRUE, residuals = "original", run_generation = 1L, seed = 123L
  )
  direct <- do.call(step3_compute, c(list(hs = hs, ss = ss), args))

  art <- file.path(root, "step2.qs2")
  qs2::qs_save(step2_share_constants(list(
    hist_sim_result = hs, new_scenarios = ss, .sig = "sig"
  )), art)
  snapshot <- c(args, list(
    artifact = list(file = art, sig = "sig"),
    hs_overlay = hs[intersect(c("hist_label", "sim_summary", ".sig"), names(hs))]
  ))

  got <- NULL
  err <- NULL
  step3_async_submit(
    snapshot, hs = hs, ss = ss,
    on_result = function(x) got <<- x,
    on_error = function(e) err <<- e
  )
  deadline <- Sys.time() + 120
  while (is.null(got) && is.null(err) && Sys.time() < deadline) {
    later::run_now(0.1)
  }
  expect_null(err)
  expect_false(is.null(got))
  expect_identical(got$pol_out$hist_sim, direct$pol_out$hist_sim)
  expect_identical(got$diagnostic_summary, direct$diagnostic_summary)
  # The job directory is removed once the result is adopted; the result file
  # is kept for the metric workers.
  expect_length(list.files(file.path(root, "step3")), 0L)
  expect_true(file.exists(got$artifact$file))

  # A metric job reads both retained artifacts and equals the in-process result.
  metric <- NULL
  metric_err <- NULL
  step3_metric_submit(
    list(
      artifact = snapshot$artifact, hs_overlay = snapshot$hs_overlay,
      policy_artifact = got$artifact["file"], residuals = "original",
      method = "mean", pov_line = NULL, requested_residuals = "original",
      endpoint_baseline = NULL, endpoint_policy = NULL, focus = NULL, unit = "hh"
    ),
    on_result = function(x) metric <<- x,
    on_error = function(e) metric_err <<- e
  )
  deadline <- Sys.time() + 120
  while (is.null(metric) && is.null(metric_err) && Sys.time() < deadline) {
    later::run_now(0.1)
  }
  expect_null(metric_err)
  expected <- .policy_metric_decomposition(
    baseline_hist = direct$baseline_out, policy_hist = direct$pol_out$hist_sim,
    baseline_scenarios = direct$baseline_scenarios_out,
    policy_scenarios = direct$pol_out$saved_scenarios %||% list(),
    prepared = direct$pol_out$annual_channels, method = "mean",
    requested_residuals = "original", analysis_unit = "hh",
    validation_cache = new.env(parent = emptyenv())
  )
  expect_identical(metric$status, "ok")
  expect_identical(metric$summary, expected$summary)
  expect_identical(metric$annual, expected$annual)
  expect_true(.wise_step3_metric_async_available(
    list(.artifact = list(file = art)), list(.artifact = got$artifact)
  ))
})

test_that("the policy arm shares household-constant vectors through a file round trip", {
  skip_if_not_installed("qs2")
  ids <- seq_len(2000L)
  pipe <- function(y) list(
    y_point = y, id_vec = ids, weight = rep(1, 2000L), svy_row_id = ids,
    sim_year = rep(2020L, 2000L),
    weather_exposure = list(schema = 2L, row_index = ids, prediction_row_id = ids)
  )
  computed <- list(
    pol_out = list(
      hist_sim = list(pipeline = pipe(rnorm(2000L))),
      saved_scenarios = list(a = list(pipelines = list(m1 = pipe(rnorm(2000L)), m2 = pipe(rnorm(2000L)))))
    ),
    decomp_context = "ctx"
  )
  shared <- .step3_share_constants(computed)
  expect_s3_class(shared$pol_out$saved_scenarios$a$pipelines$m1$id_vec, "wiseapp_shared_ref")
  # Identical vectors (ids, row maps) are stored once: ids, weights, sim_year.
  expect_length(shared$.shared_constants, 3L)

  f <- withr::local_tempfile(fileext = ".qs2")
  qs2::qs_save(shared, f)
  back <- .step3_unshare_constants(qs2::qs_read(f))
  expect_null(back$.shared_constants)
  expect_identical(back, computed)
  # Unsharing without a store is a no-op.
  expect_identical(.step3_unshare_constants(computed), computed)
})

test_that("cancelling a Step 3 job stops the running task and frees the daemon", {
  skip_on_cran()
  state <- .wise_step2_async_state
  withr::local_envvar(WISEAPP_ASYNC_SYNC = "0")
  try(mirai::daemons(0L), silent = TRUE)
  state$started <- FALSE
  withr::defer({
    try(mirai::daemons(0L), silent = TRUE)
    state$started <- FALSE
  })
  root <- withr::local_tempdir()
  withr::local_envvar(WISEAPP_ASYNC_ARTIFACT_ROOT = root)

  # A worker that would hold the daemon for a minute. It runs in the daemon, so
  # its environment must not carry the test frame.
  slow_worker <- function(snapshot, artifact_dir) {
    dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)
    Sys.sleep(60)
    "finished"
  }
  environment(slow_worker) <- globalenv()

  called <- FALSE
  job <- .wise_step3_async_task(
    slow_worker, list(),
    convert = function(value, artifact_dir) value,
    on_result = function(x) called <<- TRUE,
    on_error = function(e) called <<- TRUE
  )
  # Wait until the worker started (it creates the job directory).
  deadline <- Sys.time() + 60
  while (!dir.exists(job$artifact_dir) && Sys.time() < deadline) later::run_now(0.1)
  expect_true(dir.exists(job$artifact_dir))

  started <- proc.time()[["elapsed"]]
  expect_true(job$cancel())
  expect_false(job$cancel())
  expect_false(dir.exists(job$artifact_dir))

  # The single daemon runs the next task at once instead of after the sleep.
  next_task <- mirai::mirai(1 + 1, .compute = "default")
  deadline <- Sys.time() + 20
  while (mirai::unresolved(next_task) && Sys.time() < deadline) later::run_now(0.1)
  expect_identical(next_task$data, 2)
  expect_lt(proc.time()[["elapsed"]] - started, 20)
  later::run_now(0.5)
  expect_false(called)
})

test_that("policy fields identical to the baseline become links and are re-linked", {
  big <- function() data.frame(a = seq_len(5000L), b = rnorm(5000L))
  pipe <- function(y) list(y_point = y, weather_raw = baseline_weather, small = 1)
  baseline_weather <- big()
  hs <- list(
    weather_raw = baseline_weather, svy = big(), so = list(name = "y"),
    pipeline = pipe(rnorm(100L))
  )
  ss <- list(a = list(
    weather_shared = big(), shared_context = "ctx",
    pipelines = list(m1 = pipe(rnorm(100L)), m2 = pipe(rnorm(100L)))
  ))
  # The policy arm changes the predictions and nothing else.
  pol_out <- list(
    hist_sim = modifyList(hs, list(pipeline = modifyList(hs$pipeline, list(y_point = rnorm(100L))))),
    saved_scenarios = list(a = modifyList(ss$a, list(
      pipelines = lapply(ss$a$pipelines, function(p) modifyList(p, list(y_point = rnorm(100L))))
    )))
  )
  deduped <- .step3_dedupe_vs_baseline(pol_out, hs, ss)
  expect_true(.step3_is_link(deduped$hist_sim$weather_raw))
  expect_true(.step3_is_link(deduped$hist_sim$svy))
  expect_true(.step3_is_link(deduped$hist_sim$pipeline$weather_raw))
  expect_true(.step3_is_link(deduped$saved_scenarios$a$weather_shared))
  expect_true(.step3_is_link(deduped$saved_scenarios$a$pipelines$m1$weather_raw))
  # Changed or small fields stay.
  expect_false(.step3_is_link(deduped$hist_sim$pipeline$y_point))
  expect_identical(deduped$saved_scenarios$a$pipelines$m1$small, 1)
  expect_lt(
    length(serialize(deduped, NULL)), length(serialize(pol_out, NULL)) / 2
  )

  relinked <- .step3_relink_baseline(deduped, hs, ss)
  expect_identical(relinked, pol_out)

  # A link without a baseline field is refused.
  ss_missing <- ss
  ss_missing$a$pipelines$m1$weather_raw <- NULL
  expect_error(.step3_relink_baseline(deduped, hs, ss_missing), "baseline field")
})

test_that("member weather is released only when a worker can read it back", {
  ss <- list(
    a = list(weather_raw = "rep", pipelines = list(
      m1 = list(weather_raw = data.frame(x = 1), y_point = 1:3),
      m2 = list(weather_raw = data.frame(x = 2), y_point = 4:6)
    )),
    b = list(weather_raw = "rep", pipelines = list(m1 = list(weather_raw = data.frame(x = 3))))
  )
  expect_false(.step3_members_released(ss))
  released <- .step3_release_member_weather(ss)
  expect_true(.step3_members_released(released))
  expect_s3_class(released$a$pipelines$m2$weather_raw, "wiseapp_released_weather")
  expect_s3_class(released$b$pipelines$m1$weather_raw, "wiseapp_released_weather")
  # Everything else, including the scenario-level frame, is untouched.
  expect_identical(released$a$weather_raw, "rep")
  expect_identical(released$a$pipelines$m1$y_point, 1:3)
  expect_identical(names(released), names(ss))
  expect_false(.step3_members_released(NULL))
  expect_identical(.step3_release_member_weather(NULL), list())

  artifact <- list(file = "x", sig = "s")
  expect_true(.step3_release_allowed(artifact))
  expect_false(.step3_release_allowed(NULL))
  withr::with_envvar(c(WISEAPP_ASYNC_STEP3 = "0"), expect_false(.step3_release_allowed(artifact)))
  withr::with_envvar(c(WISEAPP_ASYNC_SYNC = "1"), expect_false(.step3_release_allowed(artifact)))
})
