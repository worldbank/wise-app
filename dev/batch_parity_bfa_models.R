# Real-data parity check for the batch Step 1 model tables (Phase 2).
#
# Runs two BFA model specs through the batch pipeline (targets, local data):
# a linear fixest model with a user covariate list, and the same model with
# covariates from the Lasso. The same selections go through the app's module
# servers (shiny::testServer on the whole Step 1 module, "Run model"), and the
# batch tables are compared with the tables the modules register for export
# (coefficients, fit statistics, headline cards, focused estimates).
# Needs WISEAPP_DATA_PATH, targets, arrow and yaml. Not part of the test suite:
# run per release.
#
# Usage: Rscript dev/batch_parity_bfa_models.R

suppressMessages({
  pkgload::load_all(".", quiet = TRUE)
  library(shiny)
})
stopifnot(nzchar(Sys.getenv("WISEAPP_DATA_PATH")))
covs <- c("hhsize", "electricity", "cellphone")

proj <- file.path(tempdir(), "batch-parity-models")
dir.create(proj, showWarnings = FALSE)
writeLines(c(
  "seed: 123",
  "outcome: {name: welfare, currency: PPP}",
  "model: {}",
  "profiles:",
  "  weather:",
  "    t_bins_r_12m:",
  "      t: {ref_period: [1, 3], form: binned, n_bins: 5}",
  "      r: {ref_period: [1, 12], form: continuous}",
  "  covariates:",
  sprintf("    user: {method: user, vars: [%s]}", paste(covs, collapse = ", ")),
  "    lasso: {method: lasso}",
  "axes:",
  "  country: [BFA]",
  "  weather: [t_bins_r_12m]",
  "  covariates: [user, lasso]"
), file.path(proj, "spec.yaml"))
writeLines(c(
  "library(targets)",
  sprintf("suppressMessages(pkgload::load_all(%s, quiet = TRUE))", deparse(normalizePath("."))),
  "tar_option_set(error = \"continue\", memory = \"transient\")",
  "wiseapp::wise_targets(\"spec.yaml\", out_dir = \"results\")"
), file.path(proj, "_targets.R"))
old <- setwd(proj)
t0 <- Sys.time()
targets::tar_make(callr_function = NULL, reporter = "silent")
setwd(old)
cat(sprintf("Batch pipeline: %.0f s\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
out <- file.path(proj, "results")
table <- function(name) dplyr::collect(arrow::open_dataset(file.path(out, "tables", name)))
fail <- arrow::read_parquet(file.path(out, "failures.parquet"))
if (nrow(fail)) print(fail)
stopifnot(nrow(fail) == 0L)
runs <- arrow::read_parquet(file.path(out, "runs.parquet"))
terms <- table("model_terms")
mfit <- table("model_fit")
vcv <- table("model_vcov")
cat("Batch tables:", nrow(terms), "model_terms,", nrow(mfit), "model_fit,", nrow(vcv), "model_vcov rows\n")
id_of <- function(label) runs$fit_id[runs$axis_covariates == label]

# The app side: the Step 1 modules on the same selections ----
cp <- build_connection_params("local", path = Sys.getenv("WISEAPP_DATA_PATH"))
md <- load_overview_metadata(cp)
app <- list()
shiny::testServer(
  mod_1_modelling_server,
  args = list(
    connection_params = shiny::reactive(cp), survey_list = shiny::reactive(md$survey_list),
    variable_list = shiny::reactive(md$variable_list), cpi_ppp = shiny::reactive(md$cpi_ppp)
  ),
  {
    session$setInputs(
      `sample-unit` = "hh", `sample-economy` = "BFA", `sample-year_BFA` = c(2018, 2021),
      `outcome-outcome` = "welfare", `outcome-currency` = "PPP",
      `weather-weather_variable_selector` = c("t", "r"),
      `weather-t_relativePeriod` = c(1, 3), `weather-t_contOrBinned` = "Binned",
      `weather-t_numBins` = 5, `weather-t_binningMethod` = "Equal frequency",
      `weather-r_relativePeriod` = c(1, 12), `weather-r_contOrBinned` = "Continuous",
      `weather-hist_years` = c(1991, 2020)
    )
    session$setInputs(`surveystats-survey_stats` = 0L)
    session$setInputs(`surveystats-survey_stats` = 1L)
    session$flushReact()
    session$setInputs(`weatherstats-weather_stats` = 0L)
    session$setInputs(`weatherstats-weather_stats` = 1L)
    session$flushReact()
    api <- session$getReturned()
    session$setInputs(
      `model-model_type` = "Linear regression", `model-interactions` = character(0),
      `model-fixedeffects` = c("year", "gaul1_code")
    )
    session$flushReact()
    run <- 0L
    fit_with <- function(method, ...) {
      session$setInputs(`model-covariates` = method, ...)
      session$flushReact()
      session$setInputs(`model-run_model` = run)
      run <<- run + 1L
      session$setInputs(`model-run_model` = run)
      session$flushReact()
      session$elapse(1000)
      session$flushReact()
      items <- wise_export_items(session)
      list(
        mf = api$model_fit(), selected = api$selected_model(),
        coef = items$model_coefficients$fun(), stats = items$model_fit_statistics$fun(),
        headline = items$step1_headline_summary$fun(), focused = items$step1_focused_estimates$fun()
      )
    }
    app$user <<- fit_with("User-defined", `model-hhcov` = covs)
    app$lasso <<- fit_with("Lasso")
  }
)
stopifnot(!is.null(app$user$mf), !is.null(app$lasso$mf))

all_ok <- TRUE
check <- function(name, ok) {
  cat(sprintf("%-66s %s\n", name, if (isTRUE(ok)) "OK" else "DIFFERS"))
  all_ok <<- isTRUE(ok) && all_ok
}
maxdiff <- function(a, b) max(abs(as.numeric(a) - as.numeric(b)))
near <- function(a, b) isTRUE(all.equal(as.numeric(a), as.numeric(b), tolerance = 1e-10))

for (label in c("user", "lasso")) {
  a <- app[[label]]
  tt <- terms[terms$fit_id == id_of(label), ]
  mf <- mfit[mfit$fit_id == id_of(label), ]
  cat(sprintf("\n-- %s covariates (%d covariates in the app model) --\n", label, length(unlist(a$selected[grepl("covariates", names(a$selected))]))))
  check(
    "covariates: same set",
    setequal(
      unique(unlist(a$selected[c("hh_covariates", "area_covariates", "ind_covariates", "firm_covariates")])),
      setdiff(tt$term[tt$model == 3L & !tt$is_weather], c("(Intercept)"))
    )
  )
  co <- a$coef
  # Batch sorts a user covariate list (equal sets hash equal); the app keeps
  # the order of the selection. Match rows by specification and term.
  key <- function(model, term) paste(model, term, sep = "|")
  ord <- match(key(as.integer(substr(co$Model, 2, 2)), co$Term), key(tt$model, tt$term))
  same_rows <- nrow(tt) == nrow(co) && !anyNA(ord)
  check("model_terms: same specifications and terms as model_coefficients", same_rows)
  if (same_rows) {
    tt <- tt[ord, ]
    # Covariate order changes floating-point noise only (about 1e-16).
    check("model_terms: estimate equal (1e-10)", near(tt$estimate, co$Estimate))
    check("model_terms: std_error equal (1e-10)", near(tt$std_error, co$`Std. error`))
    check("model_terms: p_value equal (1e-10)", near(tt$p_value, co$`p value`))
    cat(sprintf(
      "  max |diff|: estimate %.1e, std_error %.1e; identical: %s\n",
      maxdiff(tt$estimate, co$Estimate), maxdiff(tt$std_error, co$`Std. error`),
      identical(tt$estimate, co$Estimate)
    ))
  }
  fit <- mf[mf$section == "fit" & mf$model == 3L, ]
  shown <- calc_fit_stats(a$mf$fit3, FALSE)
  check(
    "model_fit: fit statistics format to the Model fit table",
    identical(
      shown$Value,
      c(formatC(fit$value[1], format = "f", digits = 0, big.mark = ","), sprintf("%.2f", fit$value[2:4]))
    ) && identical(a$stats$Value, shown$Value)
  )
  h <- mf[mf$section == "headline", ]
  check(
    "model_fit: headline cards equal step1_headline_summary",
    identical(h$statistic, a$headline$card) && identical(h$text, a$headline$value) &&
      identical(h$detail, a$headline$detail)
  )
  hit <- tt[tt$model == 3L & !is.na(tt$translation), ]
  check(
    "model_terms: translation equals step1_focused_estimates",
    identical(hit$term, a$focused$Term) && identical(hit$translation, a$focused$Translation) &&
      near(hit$estimate, a$focused$Effect)
  )
  V <- stats::vcov(a$mf$fit3)
  v <- vcv[vcv$fit_id == id_of(label), ]
  check(
    "model_vcov: weather block of the fit's covariance",
    near(v$covariance, V[cbind(v$term_1, v$term_2)])
  )
  cl <- mf$text[mf$statistic == "vcov"]
  check("clustered at the location panel", identical(cl, "clustered: loc_id_panel"))
  if (identical(label, "lasso")) {
    check("lasso_freq present on the selected covariates", any(!is.na(tt$lasso_freq[tt$model == 3L])))
  }
}
cat(if (all_ok) "\nAll checks passed.\n" else "\nSome checks differ.\n")
quit(status = if (all_ok) 0L else 1L)
