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
  rows$log_points <- rows$model_value
  rows$percent <- log_effect_to_percent(rows$model_value)
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

decomposition_channels_by_decile <- function(decomp_df, svy = NULL,
                                              outcome = "welfare") {
  if (is.null(decomp_df) || !nrow(decomp_df)) return(tibble::tibble())
  if (!is.null(svy)) {
    dec <- weighted_baseline_deciles(svy, outcome, baseline_weight_column(svy))
    ids <- suppressWarnings(as.integer(decomp_df$id))
    decomp_df$decile <- dec[ids]
  }
  w <- .decomp_weights(decomp_df)
  main <- decomp_df$delta_main %||% rep(0, nrow(decomp_df))
  res <- (decomp_df$delta_res1 %||% rep(0, nrow(decomp_df))) +
    (decomp_df$delta_res2 %||% rep(0, nrow(decomp_df)))
  total <- decomp_df$delta_total %||% (main + res)
  out <- dplyr::bind_rows(lapply(sort(unique(decomp_df$decile)), function(d) {
    ok <- decomp_df$decile == d
    tibble::tibble(
      decile = d,
      level_log = .weighted_mean_safe(main[ok], w[ok]),
      resilience_log = .weighted_mean_safe(res[ok], w[ok]),
      total_log = .weighted_mean_safe(total[ok], w[ok]),
      level_percent = log_effect_to_percent(level_log),
      resilience_percent = log_effect_to_percent(resilience_log),
      total_percent = log_effect_to_percent(total_log),
      n_households = sum(ok, na.rm = TRUE),
      weighted_population = sum(w[ok], na.rm = TRUE)
    )
  }))
  out
}

plot_decomposition_channels_by_decile <- function(tbl) {
  if (is.null(tbl) || !nrow(tbl)) {
    return(ggplot2::ggplot() + ggplot2::labs(title = "Decile decomposition is unavailable."))
  }
  long <- tidyr::pivot_longer(
    tbl[, c("decile", "level_percent", "resilience_percent")],
    cols = c("level_percent", "resilience_percent"),
    names_to = "channel", values_to = "effect"
  )
  long$channel <- dplyr::recode(long$channel,
    level_percent = "Level", resilience_percent = "Resilience"
  )
  ggplot2::ggplot(long, ggplot2::aes(x = factor(.data$decile), y = .data$effect,
                                     fill = .data$channel)) +
    ggplot2::geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
    ggplot2::geom_col(position = "dodge", width = 0.62) +
    ggplot2::geom_point(data = tbl,
                        ggplot2::aes(x = factor(.data$decile), y = .data$total_percent),
                        inherit.aes = FALSE, shape = 21, fill = "#009E73",
                        colour = "#243746", size = 2.8) +
    ggplot2::scale_fill_manual(values = c(Level = "#0072B2", Resilience = "#D55E00")) +
    ggplot2::labs(x = "Fixed observed baseline welfare decile (1 = poorest)",
                  y = "Policy effect (percent change)", fill = "Channel",
                  subtitle = "Bars show level and resilience; points show the reconciled total. Deciles use weighted observed baseline welfare.") +
    theme_wise(base_size = 12) + ggplot2::theme(legend.position = "bottom")
}
