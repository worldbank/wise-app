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
  if (!"variable" %in% names(skill)) skill$variable <- "t"
  if (!"window" %in% names(skill)) skill$window <- 1L
  skill <- skill[skill$level %in% "country" &
    as.integer(skill$init_month) == as.integer(format(as.Date(run$init), "%m")) &
    skill$skill_flag %in% .FORECAST_SKILL_FLAGS, , drop = FALSE]
  if (!nrow(skill)) NULL else skill
}

#' Skill of each target month of a window, and a one-line reading of it
#'
#' @param skill Result of `.forecast_skill_table()`, or `NULL`.
#' @param variables Weather variables of the fitted model; the table's other variables are ignored. With
#'   several variables the flag is the worst of them and `text` lists each.
#' @param run A validated run (`init`).
#' @param start,len Target window start ("YYYY-MM") and length in months.
#' @return A list: `assessed` (logical), `flag` (the flag of the window mean when the table has that
#'   window, else the worst flag over the target months, or `NA`), `months` (data frame: `month`,
#'   `lead_month`, `skill_flag`, `acc`, `crpss`) and `text`.
#' @noRd
.forecast_skill_summary <- function(skill, run, start, len, variables = NULL) {
  vars <- if (!is.null(skill) && "variable" %in% names(skill)) unique(as.character(skill$variable))
  if (!is.null(variables)) vars <- intersect(vars, variables)
  if (is.null(skill) || length(vars) <= 1L) {
    if (!is.null(skill) && "variable" %in% names(skill)) skill <- skill[skill$variable %in% vars, , drop = FALSE]
    return(.forecast_skill_one(skill, run, start, len))
  }
  parts <- lapply(vars, function(v) .forecast_skill_one(skill[skill$variable == v, , drop = FALSE], run, start, len))
  flags <- vapply(parts, function(p) p$flag, character(1))
  months <- do.call(rbind, Map(function(p, v) if (!is.null(p$months)) cbind(variable = v, p$months), parts, vars))
  assessed <- all(vapply(parts, function(p) isTRUE(p$assessed), logical(1)))
  list(
    assessed = assessed,
    flag = if (assessed) .FORECAST_SKILL_FLAGS[min(match(flags, .FORECAST_SKILL_FLAGS))] else NA_character_,
    months = months,
    text = paste(Map(function(p, v) paste0(v, ": ", p$text), parts, vars), collapse = " ")
  )
}

.forecast_skill_one <- function(skill, run, start, len) {
  targets <- seq(as.Date(paste0(start, "-01")), by = "month", length.out = as.integer(len))
  init <- as.Date(run$init)
  lead <- 1L + (as.integer(format(targets, "%Y")) - as.integer(format(init, "%Y"))) * 12L +
    (as.integer(format(targets, "%m")) - as.integer(format(init, "%m")))
  if (is.null(skill)) {
    return(list(assessed = FALSE, flag = NA_character_, months = NULL,
      text = "Forecast skill was not assessed for this run."))
  }
  # Tables without a `window` column (runs before November 2026) hold single months only.
  windows <- if ("window" %in% names(skill)) as.integer(skill$window) else rep(1L, nrow(skill))
  whole <- skill[windows == as.integer(len) & as.integer(skill$lead_month) == lead[1L], , drop = FALSE]
  skill <- skill[windows == 1L, , drop = FALSE]
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
  if (as.integer(len) > 1L && nrow(whole) == 1L) {
    flag <- as.character(whole$skill_flag)
    return(list(assessed = TRUE, flag = flag, months = months,
      text = paste0("Hindcast skill of the window mean is ", flag, ". By month: ", text)))
  }
  list(assessed = TRUE, flag = worst, months = months, text = text)
}

#' Skill summary for a selected window, reading the run's table
#' @noRd
.forecast_skill_for_window <- function(connection_params, run, start, len, variables = NULL) {
  .forecast_skill_summary(.forecast_skill_table(connection_params, run), run, start, len, variables)
}
