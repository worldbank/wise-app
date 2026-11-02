# Seasonal forecast: hindcast skill of the target months ----

# Order of the pipeline's `skill_flag` values, worst first. The flags come from thresholds fixed upstream
# (wise-app-data); the app only reads and reports them.
.FORECAST_SKILL_FLAGS <- c("none", "weak", "useful")

#' Hindcast skill table of a run, restricted to its initialization month and the country level
#'
#' Reads `run$skill_file` (verified by `.forecast_catalogue_runs()`). Columns follow
#' `forecast_skill_columns` in wise-app-data. Returns `NULL` when the run has no skill table or the
#' table cannot be read or lacks rows for the run's initialization month.
#' @noRd
.forecast_skill_table <- function(connection_params, run) {
  file <- run$skill_file %||% NA_character_
  if (length(file) != 1L || is.na(file)) return(NULL)
  skill <- tryCatch(
    as.data.frame(load_data(file, connection_params, collect = TRUE)),
    error = function(e) NULL
  )
  needed <- c("init_month", "lead_month", "level", "skill_flag")
  if (is.null(skill) || !all(needed %in% names(skill))) return(NULL)
  skill <- skill[skill$level %in% "country" &
    as.integer(skill$init_month) == as.integer(format(as.Date(run$init), "%m")) &
    skill$skill_flag %in% .FORECAST_SKILL_FLAGS, , drop = FALSE]
  if (!nrow(skill)) NULL else skill
}

#' Skill of each target month of a window, and a one-line reading of it
#'
#' @param skill Result of `.forecast_skill_table()`, or `NULL`.
#' @param run A validated run (`init`).
#' @param start,len Target window start ("YYYY-MM") and length in months.
#' @return A list: `assessed` (logical), `flag` (the worst flag over the target months, or `NA`),
#'   `months` (data frame: `month`, `lead_month`, `skill_flag`, `acc`, `crpss`) and `text`.
#' @noRd
.forecast_skill_summary <- function(skill, run, start, len) {
  targets <- seq(as.Date(paste0(start, "-01")), by = "month", length.out = as.integer(len))
  init <- as.Date(run$init)
  lead <- 1L + (as.integer(format(targets, "%Y")) - as.integer(format(init, "%Y"))) * 12L +
    (as.integer(format(targets, "%m")) - as.integer(format(init, "%m")))
  if (is.null(skill)) {
    return(list(assessed = FALSE, flag = NA_character_, months = NULL,
      text = "Forecast skill was not assessed for this run."))
  }
  hit <- match(lead, as.integer(skill$lead_month))
  col <- function(name) if (name %in% names(skill)) as.numeric(skill[[name]])[hit] else rep(NA_real_, length(hit))
  months <- data.frame(
    month = targets, lead_month = lead, skill_flag = as.character(skill$skill_flag)[hit],
    acc = col("acc"), crpss = col("crpss"), stringsAsFactors = FALSE
  )
  flags <- months$skill_flag
  if (anyNA(flags)) {
    return(list(assessed = FALSE, flag = NA_character_, months = months,
      text = "Forecast skill was not assessed for every target month."))
  }
  worst <- .FORECAST_SKILL_FLAGS[min(match(flags, .FORECAST_SKILL_FLAGS))]
  label <- function(flag) {
    m <- format(months$month[flags == flag], "%b %Y")
    if (length(m)) paste0(flag, " for ", paste(m, collapse = ", "))
  }
  groups <- Filter(Negate(is.null), lapply(.FORECAST_SKILL_FLAGS, label))
  text <- paste0(
    if (identical(worst, "none")) "No demonstrated hindcast skill: " else "Hindcast skill is ",
    paste(groups, collapse = "; "), "."
  )
  list(assessed = TRUE, flag = worst, months = months, text = text)
}

#' Skill summary for a selected window, reading the run's table
#' @noRd
.forecast_skill_for_window <- function(connection_params, run, start, len) {
  .forecast_skill_summary(.forecast_skill_table(connection_params, run), run, start, len)
}
