# Return periods: one rule, the Weibull plotting position ----
#
# Wherever the app attaches a probability of exceedance or a "1 in N" to an empirical sample of n values, the
# adverse rank m (1 = most adverse) has probability p = m / (n + 1). The level exceeded with probability p is
# R's quantile type 6, read at the adverse rank k = (n + 1) p with linear interpolation between ranks. The worst
# of n values is 1 in (n + 1), never rarer than the record allows. Spec: docs/32_metrics.md, Section 4.

#' Weibull exceedance probabilities of n ranked values
#'
#' @param n Number of values.
#' @return `seq_len(n) / (n + 1)`: the probability of the most adverse, second most adverse, ... value.
#' @noRd
rp_positions <- function(n) {
  if (!is.finite(n) || n < 1) {
    return(numeric())
  }
  seq_len(n) / (n + 1)
}

# Position of the level exceeded with probability `p` in an ascending vector of `n` values: adverse rank
# k = (n + 1) p, counted from the top when high values are adverse and from the bottom when low ones are.
# NULL when the rank falls outside 1..n (the record does not support the probability).
# Ranks are rounded to 1e-9, so that (n + 1) * p = 3 is not 3.0000000000000004.
.rp_index <- function(n, p, adverse_tail) {
  if (!is.finite(n) || n < 1 || !is.finite(p)) {
    return(NULL)
  }
  k <- round((n + 1) * p, 9)
  if (k < 1 || k > n) {
    return(NULL)
  }
  idx <- round(if (identical(adverse_tail, "high")) n + 1 - k else k, 9)
  lo <- floor(idx)
  list(index = idx, lo = as.integer(lo), hi = as.integer(ceiling(idx)), weight_hi = idx - lo)
}

#' Level exceeded with a given probability (quantile type 6)
#'
#' @param sorted Numeric vector sorted ascending, finite values. For a vector that only follows the order of
#'   another (coefficient SDs in the order of the values) the interpolation is by rank in the same way.
#' @param p Adverse exceedance probability, a scalar or a vector (1 / return period).
#' @param adverse_tail `"high"` when high values are adverse, `"low"` when low ones are.
#' @return The interpolated level, `NA_real_` when the rank `(n + 1) p` is not in `1..n`.
#' @noRd
rp_quantile <- function(sorted, p, adverse_tail = "high") {
  n <- length(sorted)
  vapply(p, function(pi) {
    i <- .rp_index(n, pi, adverse_tail)
    if (is.null(i)) {
      return(NA_real_)
    }
    sorted[[i$lo]] + i$weight_hi * (sorted[[i$hi]] - sorted[[i$lo]])
  }, numeric(1L))
}

#' Same as `rp_quantile()` for many groups at once
#'
#' One sort over all groups instead of a call per group (the Step 3 trigger thresholds run over about 10,000
#' cells on BFA).
#' @param x Finite values.
#' @param g Integer group ids in `1..n_groups`, one per value.
#' @param n_groups Number of groups.
#' @inheritParams rp_quantile
#' @return One level per group; `NA_real_` for a group without values or without support for `p`.
#' @noRd
rp_group_quantile <- function(x, g, n_groups, p, adverse_tail = "high") {
  out <- rep(NA_real_, n_groups)
  if (!length(x)) {
    return(out)
  }
  ord <- order(g, x, method = "radix")
  xs <- x[ord]
  n <- tabulate(g, n_groups)
  start <- cumsum(n) - n
  has <- which(n > 0L)
  k <- round((n[has] + 1) * p, 9)
  supported <- k >= 1 & k <= n[has]
  has <- has[supported]
  k <- k[supported]
  index <- round(if (identical(adverse_tail, "high")) n[has] + 1 - k else k, 9)
  lo <- floor(index)
  hi <- ceiling(index)
  qs <- xs[start[has] + lo]
  top <- xs[start[has] + hi]
  mix <- which(index > lo & top != qs)
  h <- (index - lo)[mix]
  qs[mix] <- (1 - h) * qs[mix] + h * top[mix]
  out[has] <- qs
  out
}

#' Exceedance probability of a level among reference values
#'
#' The reference values sit at the positions `rp_positions(n)` in the adverse order; a level between two of them
#' is read off by linear interpolation. A level more adverse than every reference value takes the end
#' probability `1 / (n + 1)` and is flagged; a level less adverse than all of them takes `n / (n + 1)`.
#' @param values Reference values (non-finite ones are dropped); at least two.
#' @param level Levels to place, a numeric vector.
#' @inheritParams rp_quantile
#' @return `NULL` without two reference values, else a data frame with one row per level: `p`, `beyond`
#'   (more adverse than every reference value) and `n_worse` (reference values strictly less adverse than
#'   the level; `n_worse = n - 1` for a level between the two most adverse values).
#' @noRd
rp_of_level <- function(values, level, adverse_tail = "high") {
  values <- values[is.finite(values)]
  n <- length(values)
  if (n < 2L) {
    return(NULL)
  }
  high <- identical(adverse_tail, "high")
  adverse_first <- sort(values, decreasing = high)
  p <- stats::approx(adverse_first, rp_positions(n), xout = level, rule = 2, ties = mean)$y
  beyond <- if (high) level > max(values) else level < min(values)
  n_worse <- vapply(level, function(v) {
    if (!is.finite(v)) NA_integer_ else sum(if (high) values < v else values > v)
  }, integer(1L))
  data.frame(p = p, beyond = !is.na(beyond) & beyond, n_worse = n_worse)
}

#' Exceedance-chart rows of one scenario: one curve per model
#'
#' Values in the adverse order at the positions `rp_positions()`, limited to the adverse half (probability
#' 0.5 or less).
#' @param mm Result of `by_model_matrix()`: `vals` and `sds` (`models x years`), `model_ids`.
#' @param scenario Scenario label.
#' @param adverse_tail `"high"` or `"low"`.
#' @param hist_ref Value subtracted (deviation views).
#' @param is_historical Logical.
#' @param source Step 3 source label (`"Baseline"` or `"Policy"`), or `NULL` for none.
#' @return A tibble: `scenario`, (`source`), `model_id`, `rank`, `welfare_val`, `coef_sd`, `exceed_prob`,
#'   `is_historical`.
#' @noRd
rp_exceedance_rows <- function(mm, scenario, adverse_tail, hist_ref, is_historical, source = NULL) {
  vals <- mm$vals
  sds <- mm$sds
  if (ncol(vals) == 0L) {
    return(NULL)
  }
  rows <- lapply(seq_len(nrow(vals)), function(i) {
    v <- vals[i, ]
    s <- sds[i, ]
    ok <- is.finite(v)
    if (!any(ok)) {
      return(NULL)
    }
    v <- v[ok]
    s <- s[ok]
    # Adverse tail: low values are adverse for welfare (ascending), high ones for poverty (descending).
    ord <- order(v, decreasing = identical(adverse_tail, "high"))
    s_ord <- if (length(s) == length(ord)) s[ord] else rep(0, length(ord))
    probs <- rp_positions(length(v))
    keep <- probs <= 0.50
    if (!any(keep)) {
      return(NULL)
    }
    out <- tibble::tibble(
      scenario = scenario,
      model_id = mm$model_ids[[i]],
      rank = seq_along(ord)[keep],
      welfare_val = v[ord][keep] - hist_ref,
      coef_sd = s_ord[keep],
      exceed_prob = probs[keep],
      is_historical = is_historical
    )
    if (!is.null(source)) out <- tibble::add_column(out, source = source, .after = "scenario")
    out
  })
  dplyr::bind_rows(rows)
}
