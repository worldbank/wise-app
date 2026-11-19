# Weather-year basis: "mean" pools every simulated year; adverse bases pick the
# 1-in-N worst baseline year within each scenario-model, using the same rule as
# Step 2 and Step 3 results (`adverse_year_support()`: rank interpolation on the
# baseline annual mean outcome, direction from the outcome) and then average the
# models equally.
.decomp_basis_probability <- c(adverse_5 = 0.20, adverse_10 = 0.10, adverse_20 = 0.05)

.decomp_basis_choices <- c(
  "Mean" = "mean", "Adverse 1-in-5" = "adverse_5",
  "Adverse 1-in-10" = "adverse_10", "Adverse 1-in-20" = "adverse_20"
)

.decomp_scenario_rows <- function(x, scenario, decile = FALSE) {
  rows <- if (decile) x$decile_summary else x$channel_summary
  rows[as.character(rows$scenario) == as.character(scenario), , drop = FALSE]
}

# One support per scenario-model, ranked on the all-household baseline level.
.decomp_adverse_supports <- function(x, scenario, basis, so) {
  rows <- .decomp_scenario_rows(x, scenario)
  probability <- .decomp_basis_probability[[basis]]
  tail <- metric_metadata("mean", so)$adverse_tail
  members <- unique(as.character(rows$member))
  supports <- lapply(members, function(m) {
    r <- rows[as.character(rows$member) == m, , drop = FALSE]
    r <- r[order(r$sim_year), , drop = FALSE]
    adverse_year_support(r$sum_baseline_level / r$weight_baseline_level,
      as.numeric(r$sim_year), probability, tail)
  })
  stats::setNames(supports, members)
}

# Equal-model average of the channel values (and baseline level) at each
# model's adverse year(s). NULL when any model lacks support.
.decomp_adverse_values <- function(rows, supports) {
  if (!length(supports)) return(NULL)
  fields <- c(.compact_decomp_channels, .compact_level_channels, "baseline_level")
  by_model <- lapply(names(supports), function(m) {
    r <- rows[as.character(rows$member) == m, , drop = FALSE]
    vapply(fields, function(f) {
      if (f %in% .compact_optional_channels && is.null(r[[paste0("sum_", f)]])) {
        return(0)
      }
      value <- r[[paste0("sum_", f)]] / r[[paste0("weight_", f)]]
      apply_adverse_year_support(value, as.numeric(r$sim_year), supports[[m]])$value
    }, numeric(1))
  })
  values <- colMeans(do.call(rbind, by_model))
  if (anyNA(values)) NULL else values
}

# One-row decomposition frame for a scenario and weather basis (empty when the
# basis is unavailable, e.g. too few simulated years for the return period).
.compact_future_decomp <- function(x, scenario, basis = "mean", so = NULL) {
  rows <- .decomp_scenario_rows(x, scenario)
  if (!nrow(rows)) return(data.frame())
  if (identical(basis, "mean")) {
    values <- .compact_future_combine(rows)
    baseline <- .compact_member_mean(rows, "sum_baseline_level", "weight_baseline_level")
  } else {
    values <- .decomp_adverse_values(rows, .decomp_adverse_supports(x, scenario, basis, so))
    if (is.null(values)) return(data.frame())
    baseline <- values[["baseline_level"]]
  }
  out <- as.data.frame(as.list(values[c(.compact_decomp_channels, .compact_level_channels)]),
    stringsAsFactors = FALSE)
  out$weight <- 1
  out$baseline_annual <- baseline
  out
}

.compact_future_decile_summary <- function(x, scenario, basis = "mean",
                                           so = NULL, is_rif = x$is_rif) {
  rows <- .decomp_scenario_rows(x, scenario, decile = TRUE)
  if (!nrow(rows)) return(tibble::tibble())
  supports <- if (identical(basis, "mean")) NULL else .decomp_adverse_supports(x, scenario, basis, so)
  out <- dplyr::bind_rows(lapply(sort(unique(rows$decile)), function(d) {
    group <- rows[rows$decile == d, , drop = FALSE]
    if (identical(basis, "mean")) {
      values <- .compact_future_combine(group)
      baseline <- .compact_member_mean(group, "sum_baseline_level", "weight_baseline_level")
    } else {
      values <- .decomp_adverse_values(group, supports)
      if (is.null(values)) return(NULL)
      baseline <- values[["baseline_level"]]
    }
    tibble::tibble(
      decile = as.integer(d),
      level_log = values[["delta_main"]],
      resilience_log = values[["delta_res"]],
      total_log = values[["delta_total"]],
      main = values[["lvl_main"]],
      shock = values[["lvl_sp_shock"]],
      repositioning = values[["lvl_res1"]],
      interaction = values[["lvl_res2"]],
      total = values[["lvl_total"]],
      level_percent = log_effect_to_percent(values[["delta_main"]]),
      resilience_percent = log_effect_to_percent(values[["delta_res"]]),
      main_percent = log_effect_to_percent(values[["delta_main"]]),
      cash_transfer_percent = log_effect_to_percent(values[["delta_sp"]]),
      shock_percent = log_effect_to_percent(values[["delta_sp_shock"]]),
      covariate_shift_percent = log_effect_to_percent(values[["delta_main_covar"]]),
      repositioning_percent = log_effect_to_percent(values[["delta_res1"]]),
      interaction_percent = log_effect_to_percent(values[["delta_res2"]]),
      total_percent = log_effect_to_percent(values[["delta_total"]]),
      n_households = sum(group$n_households),
      weighted_population = sum(group$weighted_population),
      baseline_annual = baseline
    )
  }))
  if (!nrow(out)) tibble::tibble() else out
}

#   delta_main and delta_sp are the static ones; the shock-responsive transfer is
#   `delta_sp_shock` (P2-3), so delta_main + delta_sp_shock is the old Main.
.compact_decomp_channels <- c(
  "delta_total", "delta_main", "delta_sp", "delta_main_covar",
  "delta_res", "delta_res1", "delta_res2", "delta_sp_shock"
)

# Main / repositioning / interaction / total / shock-responsive transfer in
# outcome units, converted per household before aggregation (see
# `.policy_level_channels()`). `lvl_main` is the static main effect.
.compact_level_channels <- c("lvl_main", "lvl_res1", "lvl_res2", "lvl_total", "lvl_sp_shock")

# Channels that compact frames built before P2-3 do not carry; they read as 0.
.compact_optional_channels <- c("delta_sp_shock", "lvl_sp_shock")

.bind_compact_future_decompositions <- function(parts, engine = NULL,
                                                is_rif = FALSE) {
  parts <- Filter(Negate(is.null), parts)
  if (!length(parts)) {
    return(structure(list(
      channel_summary = data.frame(),
      decile_summary = data.frame(),
      scenario_metadata = data.frame(),
      engine = engine %||% if (isTRUE(is_rif)) "rif" else "fixest",
      is_rif = isTRUE(is_rif),
      scenario_order = character(0)
    ), class = c("wise_compact_decomp_scenarios", "list")))
  }
  channel <- dplyr::bind_rows(lapply(parts, `[[`, "channel"))
  decile <- dplyr::bind_rows(lapply(parts, `[[`, "decile"))
  scenario_order <- unique(vapply(parts, function(x) x$metadata$scenario, character(1L)))
  metadata <- unique(channel[, c("scenario", "year_start", "year_end", "engine", "is_rif"),
    drop = FALSE
  ])
  structure(list(
    channel_summary = channel,
    decile_summary = decile,
    scenario_metadata = metadata,
    engine = engine %||% parts[[1L]]$engine,
    is_rif = isTRUE(is_rif),
    scenario_order = scenario_order
  ), class = c("wise_compact_decomp_scenarios", "list"))
}

.is_compact_decomp_scenarios <- function(x) {
  inherits(x, "wise_compact_decomp_scenarios")
}

.compact_future_scenarios <- function(x) {
  if (!.is_compact_decomp_scenarios(x)) {
    return(character(0))
  }
  x$scenario_order %||% unique(as.character(x$channel_summary$scenario))
}

# Equal-model mean of one summed/weighted statistic: each member's years are
# pooled first (weighted mean over its simulated years), then members are
# averaged equally, matching the Step 2 and Step 3 results. Rows without a
# `member` column (single-source frames) are treated as one member.
.compact_member_mean <- function(rows, sum_col, weight_col) {
  sums <- rows[[sum_col]]
  weights <- rows[[weight_col]]
  ok <- is.finite(sums) & is.finite(weights) & weights > 0
  if (!any(ok)) return(NA_real_)
  member <- if ("member" %in% names(rows)) as.character(rows$member) else rep("", nrow(rows))
  by_member <- vapply(split(seq_along(ok)[ok], member[ok]),
    function(i) sum(sums[i]) / sum(weights[i]), numeric(1))
  mean(by_member)
}

.compact_future_combine <- function(rows, prefix = "") {
  if (is.null(rows) || !nrow(rows)) {
    return(setNames(numeric(0), character(0)))
  }
  channels <- c(.compact_decomp_channels, .compact_level_channels)
  out <- setNames(numeric(length(channels)), channels)
  for (name in channels) {
    out[[name]] <- if (name %in% .compact_optional_channels &&
      is.null(rows[[paste0(prefix, "sum_", name)]])) {
      0
    } else {
      .compact_member_mean(
        rows, paste0(prefix, "sum_", name), paste0(prefix, "weight_", name))
    }
  }
  out
}
