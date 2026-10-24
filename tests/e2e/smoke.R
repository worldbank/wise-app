# Browser smoke test (CR-OPS-01, CR-A11Y-09): boots the real app in headless
# Chrome through shinytest2, checks one conditionalPanel and runs axe-core on
# Overview, Step 1 (sample, survey/outcome/weather stats, model results), Step 2
# (settings, results, diagnostics) and Step 3 (policy form and the four result
# tabs). Steps 1 to 3 run end to end on the small fixture data folder of
# tests/testthat/helper-batch-fixture.R (written to a temp dir), so no private
# data is needed. It lives outside tests/testthat on purpose: R CMD check and
# testthat::test_local() do not run it; the CI job (e2e-smoke) is blocking.
#
# Usage (from the repo root):
#   Rscript tests/e2e/smoke.R [path/to/axe.min.js]
# Without an argument axe-core is downloaded from cdnjs (pinned version).
# Set WISEAPP_AXE_FAIL=1 to fail on serious or critical violations. Needs
# arrow, the DuckDB h3 extension (installed on first use), shinytest2 and Chrome.
# Takes about 5 minutes.

stopifnot(file.exists("DESCRIPTION"), file.exists("app.R"))

axe_version <- "4.10.2"
args <- commandArgs(trailingOnly = TRUE)
axe_file <- if (length(args) >= 1L) args[[1L]] else {
  f <- tempfile(fileext = ".js")
  utils::download.file(
    sprintf("https://cdnjs.cloudflare.com/ajax/libs/axe-core/%s/axe.min.js", axe_version),
    f, quiet = TRUE
  )
  f
}
axe_src <- paste(readLines(axe_file, warn = FALSE), collapse = "\n")
out_dir <- Sys.getenv("WISEAPP_E2E_OUT", file.path("tests", "e2e", "out"))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Fixture data folder: the batch test fixture (metadata, two survey waves, H3
# cells, historical and CMIP6 weather) so Steps 1 to 3 run without private
# data. The helper uses testthat skips and the package's connection builder.
suppressMessages(pkgload::load_all(".", quiet = TRUE))
source(file.path("tests", "testthat", "helper-batch-fixture.R"))
data_dir <- file.path(tempfile("wise-e2e-data-"))
tryCatch(
  batch_fixture_tree(data_dir, projections = TRUE),
  skip = function(e) stop("Could not build the fixture data folder: ", conditionMessage(e), call. = FALSE)
)

# The app subprocess reads R_ENVIRON_USER, which on a developer machine can set
# WISEAPP_DATA_* to real data. Point it at a file with the fixture settings and
# the current library paths so the run is the same locally and in CI.
renviron <- tempfile("wise-e2e-", fileext = ".Renviron")
writeLines(c(
  paste0("R_LIBS=", paste(.libPaths(), collapse = .Platform$path.sep)),
  "WISEAPP_DATA_SOURCE=local",
  paste0("WISEAPP_DATA_PATH=", data_dir),
  "WISEAPP_ASYNC_SYNC=1",
  "WISEAPP_ASYNC_STEP3=0"
), renviron)
Sys.setenv(
  NOT_CRAN = "true", R_ENVIRON_USER = renviron, WISEAPP_DATA_SOURCE = "local",
  WISEAPP_DATA_PATH = data_dir, WISEAPP_ASYNC_SYNC = "1", WISEAPP_ASYNC_STEP3 = "0"
)
# The app runs in its own process and the driver connects by URL. shinytest2's
# own launcher sets warn = 2 for the whole session, which turns every warning
# in a server function into a session error; this script checks the screens,
# not warning hygiene, so it runs the app with the default warning handling.
port <- httpuv::randomPort()
app_log <- file.path(out_dir, "app.log")
server <- processx::process$new(
  file.path(R.home("bin"), "Rscript"),
  c("-e", sprintf(paste(
    "pkgload::load_all(export_all = FALSE, helpers = FALSE, attach_testthat = FALSE, quiet = TRUE);",
    "options(golem.app.prod = TRUE);",
    "shiny::runApp(wiseapp::run_app(), port = %dL, launch.browser = FALSE)"
  ), port)),
  stdout = app_log, stderr = "2>&1", cleanup = TRUE
)
on.exit(server$kill(), add = TRUE)
app_url <- sprintf("http://127.0.0.1:%d/", port)
for (i in seq_len(180L)) {
  up <- isTRUE(tryCatch({ readLines(url(app_url), n = 1L, warn = FALSE); TRUE }, error = function(e) FALSE, warning = function(w) FALSE))
  if (up || !server$is_alive()) break
  Sys.sleep(0.5)
}
if (!up) stop("The app did not start; log: ", app_log, call. = FALSE)
app <- shinytest2::AppDriver$new(
  app_url, name = "smoke", load_timeout = 90 * 1000, timeout = 30 * 1000
)
on.exit(app$stop(), add = TRUE)

failures <- character()
check <- function(ok, label) {
  cat(if (isTRUE(ok)) "ok   " else "FAIL ", label, "\n", sep = "")
  if (!isTRUE(ok)) failures <<- c(failures, label)
}

# Drive helpers ----
# A click on a missing element would be a silent no-op, and the screen scanned
# afterwards the wrong one; fail instead.
click_js <- function(sel) {
  ok <- app$get_js(sprintf("(function(){var e = document.querySelector(\"%s\"); if (!e) return false; e.click(); return true;})()", sel))
  if (!isTRUE(ok)) stop("Nothing to click for ", sel, call. = FALSE)
  invisible(TRUE)
}
# Wait for a JavaScript condition (Shiny runs fit and simulation work in the
# main process here, so "idle" is not enough on its own).
wait_for <- function(js, label, timeout = 120) {
  t0 <- Sys.time()
  while (!isTRUE(app$get_js(js)) && as.numeric(Sys.time() - t0, units = "secs") < timeout) Sys.sleep(0.5)
  ok <- isTRUE(app$get_js(js))
  check(ok, label)
  invisible(ok)
}
settle <- function(secs = 1.5) {
  # Idle can fail to settle while a long output renders; the checks that follow
  # wait on the page state itself.
  tryCatch(app$wait_for_idle(duration = 500, timeout = 60 * 1000), error = function(e) NULL)
  Sys.sleep(secs)
}
# Click a visible accordion button or sub-tab link by its text / data-value
# inside the active top-level pane.
open_panel <- function(text) {
  ok <- app$get_js(sprintf(
    "(function(){var b = [...document.querySelectorAll('button.accordion-button')].find(b => b.offsetParent !== null && b.textContent.replace(/\\s+/g, ' ').trim() === '%s'); if (!b) return false; b.click(); return true;})()", text
  ))
  if (!isTRUE(ok)) stop("No accordion panel '", text, "'", call. = FALSE)
  settle(1)
}
open_tab <- function(value) {
  ok <- app$get_js(sprintf(
    "(function(){var a = [...document.querySelectorAll('.tab-pane.active a[data-value=\"%s\"]')].find(a => a.offsetParent !== null); if (!a) return false; a.click(); return true;})()", value
  ))
  if (!isTRUE(ok)) stop("No visible tab '", value, "'", call. = FALSE)
  settle()
  # A scan of the wrong or an empty pane would pass axe, so each tab must be
  # the active one and hold content.
  wait_for(
    sprintf(
      "(function(){var a = [...document.querySelectorAll('.tab-pane.active a[data-value=\"%s\"]')].find(a => a.offsetParent !== null); var p = a && document.querySelector(a.getAttribute('href')); return !!a && a.classList.contains('active') && !!p && p.classList.contains('active') && p.innerText.trim().length > 40;})()",
      value
    ),
    sprintf("tab '%s' is active and has content", value), timeout = 30
  )
  settle(1)
}
open_step <- function(value) {
  click_js(sprintf(".navbar .nav-link[data-value='%s']", value))
  settle(1)
  check(
    isTRUE(app$get_js(sprintf("!!document.querySelector(\".navbar .nav-link.active[data-value='%s']\")", value))),
    sprintf("top-level tab '%s' is active", value)
  )
}

# Boot ----
errors <- app$get_logs()
errors <- errors[errors$level == "error" & errors$location == "shiny", , drop = FALSE]
check(nrow(errors) == 0L, "no Shiny errors in the log after boot")
tabs <- app$get_js("[...document.querySelectorAll('.navbar .nav-link')].map(e => e.textContent.trim())")
check(any(grepl("Overview", tabs)) && any(grepl("Step 3", tabs)), "navbar shows Overview and Step 3")
check(isTRUE(app$get_js("!!document.querySelector('#main-content')")), "main landmark present")

# axe-core on one screen ----
# Known upstream issue, filtered out below: bslib gives the navbar role=tablist
# while it also holds plain links (Docs, Data, GitHub) and a dropdown, so axe
# reports aria-required-children on `.navbar-nav`. Not fixable without
# dropping the tab semantics.
# Shiny notifications are excluded: they fade in and out (opacity below 1 reads
# as a color-contrast failure for a moment) and close by themselves, so a scan
# would pass or fail depending on timing. Steady-state they meet contrast
# (checked once by hand on the fixture warnings).
run_axe <- function(label) {
  app$run_js(axe_src)
  res <- app$get_js(
    "axe.run({exclude: [['#shiny-notification-panel']]}, {runOnly: {type: 'tag', values: ['wcag2a','wcag2aa','wcag21aa','wcag22aa']}}).then(r => JSON.stringify(r.violations.map(v => (v.id === 'aria-required-children' ? Object.assign({}, v, {nodes: v.nodes.filter(n => n.target.join(' ') !== '.navbar-nav')}) : v)).filter(v => v.nodes.length).map(v => ({id: v.id, impact: v.impact, help: v.help, nodes: v.nodes.length, targets: v.nodes.slice(0, 6).map(n => n.target.join(' '))}))))",
    timeout = 60 * 1000
  )
  v <- jsonlite::fromJSON(res)
  writeLines(res, file.path(out_dir, sprintf("axe-%s.json", label)))
  if (length(v) == 0L) {
    cat("axe ", label, ": no violations\n", sep = "")
    return(invisible(0L))
  }
  cat("axe ", label, ": ", nrow(v), " violation type(s)\n", sep = "")
  print(v[, c("id", "impact", "nodes", "help")], row.names = FALSE)
  for (i in seq_len(nrow(v))) cat("  ", v$id[[i]], ": ", paste(v$targets[[i]], collapse = " ; "), "\n", sep = "")
  invisible(sum(v$impact %in% c("serious", "critical")))
}
bad <- 0L
# `expect` is a CSS selector that must be visible, so the scan covers the screen
# it is named after.
scan <- function(label, expect = NULL) {
  if (!is.null(expect)) {
    wait_for(
      sprintf("(function(){var e = document.querySelector(\"%s\"); return !!e && e.offsetParent !== null;})()", expect),
      sprintf("%s: '%s' is visible", label, expect), timeout = 30
    )
  }
  bad <<- bad + run_axe(label)
}
visible <- function(sel) app$get_js(sprintf(
  "(function(){var e = document.querySelector(\"%s\"); return !!e && e.offsetParent !== null;})()", sel
))

bad <- run_axe("overview")
check(isTRUE(app$get_js("document.body.innerText.includes('Connected to')")), "Overview connects to the fixture data")

# Step 1: sample, outcome, weather, model, then the result tabs ----
open_step("step1")
# The Sample panel is open on load.
click_js("#step1-surveystats-survey_stats")
settle(3)
scan("step1-sample", "#step1-surveystats-survey_stats")
open_tab("desc_stats")
scan("step1-survey-stats", "#step1-surveystats-outcome_stats .rt-table")
open_panel("2 Outcome")
click_js("#step1-outcome-outcome_stats_btn")
settle(3)
open_tab("outcome_stats_tab")
scan("step1-outcome")
open_panel("3 Weather")
click_js("#step1-weatherstats-weather_stats")
settle(3)
open_tab("weather_desc")
scan("step1-weather", "#step1-weatherstats-weather_stats_table_binned .rt-table")
open_panel("4 Model")
click_js("#step1-model-run_model")
wait_for("document.body.innerText.includes('Step 1 (model): complete')", "Step 1 model fits on the fixture")
settle()
open_tab("results")
scan("step1-results", "#step1-results-focused_table .rt-table")
open_tab("model_fit")
scan("step1-model-fit")

# Step 2: conditionalPanel, run, results and diagnostics ----
open_step("step2")
# The settings block is itself behind a toggle (a conditionalPanel on its click count).
click_js("[id$='weathersim-settings_toggle']")
Sys.sleep(1)
sel_parent <- "input[id$='include_coef_uncertainty']"
sel_child <- "input[id$='propagate_all_covariate_uncertainty']"
check(isTRUE(app$get_js(sprintf("!!document.querySelector(\"%s\")", sel_parent))), "Step 2 coefficient-uncertainty checkbox renders")
check(visible(sel_child), "sub-option visible while the parent is checked")
click_js(sel_parent)
Sys.sleep(0.5)
check(!visible(sel_child), "sub-option hidden after the parent is unchecked")
click_js(sel_parent)
scan("step2-settings")
click_js("#step2-weathersim-run_sim")
wait_for("document.body.innerText.includes('Step 2 (climate scenarios): complete')", "Step 2 simulation runs on the fixture")
settle(2)
open_tab("sim_tab")
scan("step2-results", "#step2-results-summary_threshold_table .rt-table")
open_tab("diag_tab")
scan("step2-diagnostics")

# Step 3: social protection, run, result tabs ----
open_step("step3")
scan("step3-overview", "#step3-run_policy_sim")
stopifnot(isTRUE(app$get_js("(function(){var b = [...document.querySelectorAll('button')].find(b => b.offsetParent !== null && b.textContent.trim() === 'Social protection'); if (!b) return false; b.click(); return true;})()")))
settle(1)
app$run_js("(function(){var e = document.querySelector('#step3-sp-transfer_amount_usd'); e.value = '1'; e.dispatchEvent(new Event('input', {bubbles: true})); e.dispatchEvent(new Event('change', {bubbles: true}));})()")
settle(1)
scan("step3-social-protection")
click_js("#step3-run_policy_sim")
wait_for("document.body.innerText.includes('Step 3 (policy scenarios): complete')", "Step 3 policy simulation runs on the fixture")
settle(2)
for (v in c("results_tab", "diag_tab", "decomposition_tab", "cost_effectiveness_tab")) {
  open_tab(v)
  scan(
    paste0("step3-", sub("_tab$", "", v)),
    switch(v,
      results_tab = "#step3-results3-summary_threshold_table .rt-table",
      diag_tab = "#step3-diagnostics-diag_summary_table .rt-table"
    )
  )
}

if (length(failures)) {
  stop("Smoke checks failed: ", paste(failures, collapse = "; "), call. = FALSE)
}
if (identical(Sys.getenv("WISEAPP_AXE_FAIL"), "1") && bad > 0L) {
  stop(bad, " serious or critical axe violation type(s).", call. = FALSE)
}
cat("smoke ok\n")
