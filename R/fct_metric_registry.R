# ============================================================================ #
# Metric metadata used by result summaries and visualisations.
# ============================================================================ #

.WISE_METRIC_REGISTRY <- list(
  mean = list(label = "Mean", unit = "outcome units", format = "number"),
  median = list(label = "Median", unit = "outcome units", format = "number"),
  total = list(label = "Total", unit = "outcome units", format = "number"),
  headcount_ratio = list(label = "Poverty rate", unit = "share", format = "percent", direction = "lower_is_better"),
  gap = list(label = "Poverty gap", unit = "share", format = "percent", direction = "lower_is_better"),
  fgt2 = list(label = "Poverty severity", unit = "share", format = "percent", direction = "lower_is_better"),
  gini = list(label = "Gini coefficient", unit = "index", format = "number", direction = "lower_is_better"),
  prosperity_gap = list(label = "Prosperity gap", unit = "ratio", format = "number", direction = "lower_is_better"),
  avg_poverty = list(label = "Average poverty", unit = "days per dollar", format = "number", direction = "lower_is_better")
)

#' Return the metadata contract for a displayed metric.
#'
#' Direction comes from selected outcome metadata whenever available. This
#' prevents plot code from inferring whether a larger value is adverse.
#' @noRd
metric_metadata <- function(method = "mean", so = NULL) {
  method <- as.character(method %||% "mean")[1]
  fallback_labels <- c(
    mean = "Mean", median = "Median", total = "Total",
    headcount_ratio = "Poverty rate", gap = "Poverty gap",
    fgt2 = "Poverty severity", gini = "Gini coefficient",
    prosperity_gap = "Prosperity gap", avg_poverty = "Average poverty"
  )
  out <- .WISE_METRIC_REGISTRY[[method]] %||% list(
    label = unname(fallback_labels[[method]] %||% method),
    unit = "outcome units", format = "number"
  )
  direction <- out$direction %||% NULL
  if (!is.null(so)) {
    so_direction <- if (is.data.frame(so) && "direction" %in% names(so)) {
      so$direction[[1]]
    } else if (is.list(so)) {
      so$direction %||% NULL
    } else NULL
    if (!is.null(so_direction) && nzchar(as.character(so_direction))) {
      direction <- as.character(so_direction)[1]
    }
  }
  if (is.null(direction) || !direction %in% c("higher_is_better", "lower_is_better")) {
    direction <- "higher_is_better"
  }
  out$method <- method
  out$label <- out$label %||% unname(fallback_labels[[method]] %||% method)
  out$direction <- direction
  out$adverse_tail <- if (identical(direction, "lower_is_better")) "high" else "low"
  out$adverse_note <- if (identical(out$adverse_tail, "high")) {
    "Higher values are adverse"
  } else {
    "Lower values are adverse"
  }
  out
}

metric_axis_label <- function(method = "mean", so = NULL, deviation = "none") {
  spec <- metric_metadata(method, so)
  label <- if (identical(deviation, "none")) spec$label else {
    paste0(spec$label, " - ", label_deviation(deviation))
  }
  unit <- switch(spec$format,
    percent = "percent",
    spec$unit %||% "outcome units"
  )
  paste0(label, " (", unit, ")")
}

metric_adverse_probabilities <- function() {
  c("Adverse 1-in-5" = 0.10, "Adverse 1-in-10" = 0.05,
    "Adverse 1-in-20" = 0.025)
}

# Add the definitions needed to interpret a chart-data export. Keeping these
# fields beside the values makes a CSV useful outside the live Shiny session.
visualization_export_metadata <- function(method = "mean", so = NULL,
                                          observation_unit,
                                          aggregation_order,
                                          uncertainty = "none") {
  spec <- metric_metadata(method, so)
  data.frame(
    metric_id = spec$method,
    metric_label = spec$label,
    unit = spec$unit,
    number_format = spec$format,
    direction = spec$direction,
    adverse_tail = spec$adverse_tail,
    observation_unit = observation_unit,
    aggregation_order = aggregation_order,
    uncertainty_type = uncertainty,
    stringsAsFactors = FALSE
  )
}

annotate_visualization_export <- function(data, method = "mean", so = NULL,
                                          observation_unit,
                                          aggregation_order,
                                          uncertainty = "none") {
  if (is.null(data) || !is.data.frame(data)) return(data)
  meta <- visualization_export_metadata(
    method, so, observation_unit, aggregation_order, uncertainty
  )
  for (nm in names(meta)) data[[nm]] <- meta[[nm]][[1L]]
  data
}
