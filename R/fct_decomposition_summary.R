# ============================================================================ #
# Step 3 decomposition summaries and headline reconciliation.                 #
# ============================================================================ #

.weighted_mean_safe <- function(x, w) {
  ok <- is.finite(x) & is.finite(w) & w > 0
  if (!any(ok)) return(NA_real_)
  stats::weighted.mean(x[ok], w[ok])
}

.decomp_weights <- function(decomp_df) {
  w <- if ("weight" %in% names(decomp_df)) {
    suppressWarnings(as.numeric(decomp_df$weight))
  } else rep(1, nrow(decomp_df))
  w[!is.finite(w) | w < 0] <- NA_real_
  w
}

decomposition_summary_data <- function(decomp_df, is_rif = TRUE,
                                        tolerance = 1e-10) {
  if (is.null(decomp_df) || !is.data.frame(decomp_df) || !nrow(decomp_df)) {
    return(tibble::tibble())
  }
  w <- .decomp_weights(decomp_df)
  zero <- rep(0, nrow(decomp_df))
  main <- decomp_df$delta_main %||% zero
  res1 <- if (is_rif) decomp_df$delta_res1 %||% zero else zero
  res2 <- decomp_df$delta_res2 %||% zero
  direct_total <- decomp_df$delta_total %||% (main + res1 + res2)
  level <- main
  resilience <- res1 + res2
  rows <- tibble::tibble(
    channel_id = c("total", "level", "cash_transfer", "covariate_shift",
                   "resilience", "repositioning", "interaction"),
    channel = c("Total", "Level", "Cash transfer", "Covariate shift",
                "Resilience", "Repositioning", "Interaction"),
    parent = c(NA_character_, "total", "level", "level", "total",
               "resilience", "resilience"),
    model_value = c(
      .weighted_mean_safe(direct_total, w),
      .weighted_mean_safe(level, w),
      .weighted_mean_safe(decomp_df$delta_sp %||% zero, w),
      .weighted_mean_safe(decomp_df$delta_main_covar %||% (main - (decomp_df$delta_sp %||% zero)), w),
      .weighted_mean_safe(resilience, w),
      .weighted_mean_safe(res1, w),
      .weighted_mean_safe(res2, w)
    ),
    stringsAsFactors = FALSE
  )
  total <- rows$model_value[[1L]]
  level_value <- rows$model_value[[2L]]
  resilience_value <- rows$model_value[[5L]]
  reconciled_total <- level_value + resilience_value
  residual <- total - reconciled_total
  rows$percent <- (exp(rows$model_value) - 1) * 100
  rows$share_of_total <- if (is.finite(total) && abs(total) > tolerance &&
                             abs(total) >= 0.01 * sum(abs(c(level_value, resilience_value)))) {
    rows$model_value / total
  } else rep(NA_real_, nrow(rows))
  rows$is_rif <- is_rif
  attr(rows, "reconciliation") <- list(
    total = total,
    level_plus_resilience = reconciled_total,
    residual = residual,
    tolerance = tolerance,
    status = if (is.finite(residual) && abs(residual) <= tolerance) "reconciled" else "not_reconciled"
  )
  rows
}

decomposition_reconciliation <- function(summary_df) {
  attr(summary_df, "reconciliation") %||% list(
    status = "unavailable", residual = NA_real_, tolerance = NA_real_
  )
}

plot_decomposition_headline <- function(summary_df,
                                        y_label = "Policy effect (percent change)") {
  if (is.null(summary_df) || !nrow(summary_df)) {
    return(ggplot2::ggplot() + ggplot2::labs(title = "Decomposition is unavailable."))
  }
  ids <- c("level", "resilience", "total")
  df <- summary_df[summary_df$channel_id %in% ids, , drop = FALSE]
  df$channel <- factor(df$channel, levels = c("Level", "Resilience", "Total"))
  ggplot2::ggplot(df, ggplot2::aes(x = .data$channel, y = .data$percent,
                                   fill = .data$channel)) +
    ggplot2::geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
    ggplot2::geom_col(width = 0.62, colour = "#243746") +
    ggplot2::scale_fill_manual(values = c(Level = "#0072B2", Resilience = "#D55E00",
                                           Total = "#009E73"), guide = "none") +
    ggplot2::labs(x = NULL, y = y_label,
                  subtitle = "Level plus resilience equals the directly computed total on the model scale.") +
    theme_wise(base_size = 12)
}

decomposition_explanation <- function(is_rif) {
  if (is_rif) {
    list(
      title = "RIF decomposition: level and resilience channels",
      text = paste(
        "Level includes the cash transfer and covariate shift.",
        "Resilience includes repositioning along the estimated welfare-quantile",
        "weather-sensitivity curve and the weather-policy interaction.",
        "RIF interpolation is limited to the estimated quantile grid."
      )
    )
  } else {
    list(
      title = "OLS decomposition: level and interaction channels",
      text = paste(
        "OLS has no repositioning channel because its weather coefficients are",
        "constant. Level includes the cash transfer and covariate shift; resilience",
        "is represented by the weather-policy interaction only."
      )
    )
  }
}
