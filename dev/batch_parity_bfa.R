# Real-data parity check for the batch pipeline (Phase 1 tables).
#
# Runs one BFA spec through the batch pipeline (targets, local data) and
# through the app's own module servers (shiny::testServer with the same
# selections), then compares the batch tables with the tables the modules'
# export closures build. Needs WISEAPP_DATA_PATH, targets, arrow and yaml.
# Not part of the test suite: run per release.
#
# Usage: Rscript dev/batch_parity_bfa.R

suppressMessages({
  pkgload::load_all(".", quiet = TRUE)
  library(shiny)
})
stopifnot(nzchar(Sys.getenv("WISEAPP_DATA_PATH")))

proj <- file.path(tempdir(), "batch-parity")
dir.create(proj, showWarnings = FALSE)
writeLines(c(
  "seed: 123",
  "outcome: {name: welfare, currency: PPP}",
  "profiles:",
  "  weather:",
  "    t_bins_r_12m:",
  "      t: {ref_period: [1, 3], form: binned, n_bins: 5}",
  "      r: {ref_period: [1, 12], form: continuous}",
  "axes:",
  "  country: [BFA]",
  "  weather: [t_bins_r_12m]"
), file.path(proj, "spec.yaml"))
writeLines(c(
  "library(targets)",
  sprintf("suppressMessages(pkgload::load_all(%s, quiet = TRUE))", deparse(normalizePath("."))),
  "tar_option_set(error = \"continue\", memory = \"transient\")",
  "wiseapp::wise_targets(\"spec.yaml\", out_dir = \"results\")"
), file.path(proj, "_targets.R"))
old <- setwd(proj)
targets::tar_make(callr_function = NULL, reporter = "silent")
setwd(old)
out <- file.path(proj, "results")
table <- function(name) dplyr::collect(arrow::open_dataset(file.path(out, "tables", name)))
vs <- table("variable_stats")
idt <- table("interview_dates")
wx <- table("weather_stats")
cat("Batch tables:", nrow(vs), "variable_stats,", nrow(idt), "interview_dates,", nrow(wx), "weather_stats rows\n")
fail <- arrow::read_parquet(file.path(out, "failures.parquet"))
stopifnot(nrow(fail) == 0L)

# The app side: the modules on the same selections ----
cp <- build_connection_params("local", path = Sys.getenv("WISEAPP_DATA_PATH"))
md <- load_overview_metadata(cp)
app <- NULL
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
    app <<- list(
      survey_data = api$survey_data(), survey_weather = api$survey_weather(),
      outcome = api$selected_outcome(), weather = api$selected_weather()
    )
  }
)
stopifnot(!is.null(app$survey_data), !is.null(app$survey_weather))
sd <- app$survey_data
od <- wise_outcome_data(sd, app$outcome, app$outcome)
vl <- md$variable_list

# 1. Survey summary tables (hh, area, policy, outcome) ----
base <- stats_display_base(od, vl, wise_stats_vars(vl, od))
check <- function(name, ok) {
  cat(sprintf("%-60s %s\n", name, if (isTRUE(ok)) "OK" else "DIFFERS"))
  isTRUE(ok)
}
all_ok <- TRUE
clean <- function(x) {
  x <- gsub("<br>", " ", x, fixed = TRUE)
  x <- gsub("&gt;", ">", gsub("&lt;", "<", gsub("&amp;", "&", x, fixed = TRUE), fixed = TRUE), fixed = TRUE)
  gsub("\\s+", " ", x)
}
for (flag in c("outcome", "hh", "area")) {
  tab <- build_stats_table(od, vl, flag, base = base)
  tab$variable <- vl$name[match(clean(tab$Variable), clean(vl$label))]
  tab$wave <- sub(".*, ", "", tab$`Country, Year`)
  mine <- vs[vs$var_group == flag & vs$sample == "all" & vs$wave != "All", ]
  m <- merge(tab, mine, by = c("variable", "wave"), suffixes = c(".app", ""))
  ok <- nrow(m) == nrow(tab) &&
    identical(as.numeric(m$Mean), as.numeric(m$mean)) &&
    identical(as.numeric(m$`Std. Dev.`), as.numeric(m$sd)) &&
    identical(as.numeric(m$`% Missing`), as.numeric(m$pct_missing)) &&
    identical(as.integer(m$N), as.integer(m$n))
  all_ok <- check(sprintf("variable_stats vs survey_summary_%s (%d rows)", flag, nrow(tab)), ok) && all_ok
}

# 2. Outcome summary (deciles) ----
osw <- outcome_summary_wide(od, "welfare", "numeric")
deciles <- paste0("p", seq(10, 90, 10))
for (w in c("2018", "2021")) {
  r <- vs[vs$variable == "welfare" & vs$sample == "all" & vs$wave == w & vs$var_group == "outcome", ]
  all_ok <- check(
    paste("welfare deciles, wave", w),
    identical(unlist(r[deciles], use.names = FALSE), unname(osw$mat[deciles, paste("BFA", w, "EHCVM", sep = "|")]))
  ) && all_ok
}

# 3. Interview dates ----
app_idt <- summarise_interview_dates(od)
m <- idt[!is.na(idt$month), ]
all_ok <- check(
  "interview_dates monthly counts",
  identical(as.integer(m$n), as.integer(app_idt$hh)) && identical(as.integer(m$month), as.integer(app_idt$month_num))
) && all_ok

# 4. Weather statistics (continuous variable r) ----
sw <- app$weather
app_wx <- build_weather_stats_table(function() app$survey_weather, function() sw[sw$name == "r", ], function() sd)
mine <- wx[wx$variable == "r" & wx$source == "survey" & wx$sample == "all" & wx$wave != "All", ]
m <- merge(
  data.frame(wave = sub(".*, ", "", app_wx$`Country, Year`), app_wx, check.names = FALSE),
  mine, by = "wave"
)
all_ok <- check(
  "weather_stats r (survey) vs weather_summary",
  nrow(m) == nrow(app_wx) &&
    identical(as.numeric(m$Mean), as.numeric(m$mean)) &&
    identical(as.numeric(m$`Std. Dev.`), as.numeric(m$sd)) &&
    identical(as.numeric(m$`% Missing`), as.numeric(m$pct_missing)) &&
    identical(as.integer(m$N), as.integer(m$n))
) && all_ok

# 5. The binned variable: batch loads t continuous; the app's continuous
#    companion (values before binning) must be the same numbers ----
hy <- c(from = 1991L, to = 2020L)
ss <- app_ss <- wise_select_surveys(md$survey_list, "hh", cp, "BFA")
binned <- wise_weather_fetch(sd, ss, sw[sw$name == "t", ], hy, cp, 123L)
cont_sw <- sw[sw$name == "t", ]
cont_sw$cont_binned <- "Continuous"
cont <- wise_weather_fetch(sd, ss, cont_sw, hy, cp, 123L)
keys <- c("code", "year", "survname", "loc_id", "timestamp")
j <- merge(attr(binned, "continuous_weather")[c(keys, "t")], cont$historical[c(keys, "t")], by = keys)
all_ok <- check(
  "binned t: continuous companion equals the continuous load",
  nrow(j) == nrow(cont$historical) && identical(j$t.x, j$t.y)
) && all_ok

cat(if (all_ok) "\nAll checks passed.\n" else "\nSome checks differ.\n")
quit(status = if (all_ok) 0L else 1L)
