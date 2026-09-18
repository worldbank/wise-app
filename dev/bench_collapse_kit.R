#!/usr/bin/env Rscript

# Targeted local benchmarks for R-side collapse/kit candidates.
# This file intentionally does not change production implementations.

suppressPackageStartupMessages({
  library(bench)
  library(collapse)
  library(kit)
  library(dplyr)
})

if (file.exists(file.path("R", "fct_aggregation.R"))) {
  source(file.path("R", "fct_aggregation.R"))
}

seed <- 20260908L
set.seed(seed)

make_fixture <- function(n, groups, p = 4L) {
  group <- sample.int(groups, n, replace = TRUE)
  x <- matrix(rnorm(n * p), nrow = n, ncol = p)
  x[sample(length(x), size = floor(length(x) * 0.03))] <- NA_real_
  colnames(x) <- paste0("x", seq_len(p))
  data.frame(
    group = group,
    code = sample(sprintf("C%02d", seq_len(max(2L, groups %/% 10L))), n, TRUE),
    year = sample(2010:2020, n, TRUE),
    loc_id = sample(sprintf("L%04d", seq_len(max(10L, groups))), n, TRUE),
    weight = rexp(n, rate = 1),
    x,
    check.names = FALSE
  )
}

weighted_mean_base <- function(x, w, g) {
  out <- tapply(seq_along(x), g, function(i) {
    ok <- is.finite(x[i]) & is.finite(w[i]) & w[i] > 0
    if (!any(ok)) return(NA_real_)
    sum(x[i][ok] * w[i][ok]) / sum(w[i][ok])
  })
  as.numeric(out)
}

weighted_mean_collapse <- function(x, w, g) {
  ok <- is.finite(x) & is.finite(w) & w > 0
  out <- collapse::fsum(x * w, g = g, na.rm = TRUE) /
    collapse::fsum(w * ok, g = g, na.rm = TRUE)
  as.numeric(out)
}

group_summary_base <- function(d) {
  dplyr::summarise(
    dplyr::group_by(d, group),
    n = dplyr::n(),
    mean_x1 = mean(x1, na.rm = TRUE),
    sd_x1 = stats::sd(x1, na.rm = TRUE),
    sum_x2 = sum(x2, na.rm = TRUE),
    .groups = "drop"
  )
}

group_summary_collapse <- function(d) {
  collapse::collap(
    d[c("x1", "x2")],
    d["group"],
    FUN = collapse::fmean,
    na.rm = TRUE,
    keep.col.order = TRUE
  )
}

group_mean_base <- function(d) {
  dplyr::summarise(
    dplyr::group_by(d, group),
    x1 = mean(x1, na.rm = TRUE),
    x2 = mean(x2, na.rm = TRUE),
    .groups = "drop"
  )
}

group_mean_collapse <- function(d) {
  collapse::collap(
    d[c("x1", "x2")], d["group"],
    FUN = collapse::fmean,
    na.rm = TRUE,
    keep.by = TRUE,
    keep.col.order = TRUE
  )
}

key_index_base <- function(d) {
  key <- interaction(d$code, d$year, d$loc_id, drop = TRUE, lex.order = TRUE)
  split(seq_len(nrow(d)), key, drop = TRUE)
}

key_index_kit <- function(d) {
  key <- paste(d$code, d$year, d$loc_id, sep = "\001")
  kit::funique(key)
}

quantiles_base <- function(x, g) {
  lapply(split(x, g), stats::quantile, probs = c(.1, .5, .9), na.rm = TRUE)
}

quantiles_collapse <- function(x, g) {
  # collapse has fast grouped quantiles through fquantile with GRP slices.
  grp <- collapse::GRP(g)
  out <- vector("list", grp$N.groups)
  ord <- order(grp$group.id, method = "radix")
  starts <- cumsum(c(1L, head(tabulate(grp$group.id), -1L)))
  sizes <- tabulate(grp$group.id)
  for (i in seq_len(grp$N.groups)) {
    idx <- ord[starts[i]:(starts[i] + sizes[i] - 1L)]
    out[[i]] <- collapse::fquantile(x[idx], probs = c(.1, .5, .9), na.rm = TRUE)
  }
  out
}

aggregate_mean_base <- function(d) {
  aggregate_outcome(d, "x1", group = "group", aggregate = "mean", weights = "weight")
}

aggregate_mean_collapse <- function(d) {
  g <- collapse::GRP(d["group"])
  values <- collapse::fsum(d$x1 * d$weight, g = g, na.rm = TRUE) /
    collapse::fsum(d$weight, g = g, na.rm = TRUE)
  data.frame(group = g$groups$group, value = as.numeric(values))
}

aggregate_mean_dplyr_reference <- function(d) {
  dplyr::summarise(
    dplyr::group_by(d, group),
    value = sum(x1 * weight, na.rm = TRUE) / sum(weight, na.rm = TRUE),
    .groups = "drop"
  )
}

run_case <- function(label, d, expr, check = NULL, iterations = 5L) {
  expr_call <- substitute(expr)
  expr_env <- parent.frame()
  bm <- bench::mark(
    result <- eval(expr_call, envir = expr_env),
    iterations = iterations,
    check = FALSE,
    memory = TRUE,
    time_unit = "ms"
  )
  value <- eval(expr_call, envir = expr_env)
  if (!is.null(check)) check(value)
  data.frame(
    case = label,
    median_ms = as.numeric(stats::median(bm$median)) * 1000,
    mem_alloc_mb = as.numeric(stats::median(bm$mem_alloc)) / 1024^2,
    result_bytes = as.numeric(object.size(value)),
    stringsAsFactors = FALSE
  )
}

fixtures <- list(
  LKA = make_fixture(250000L, 3000L),
  IND = make_fixture(1000000L, 12000L)
)

results <- list()
for (country in names(fixtures)) {
  d <- fixtures[[country]]
  base_wm <- weighted_mean_base(d$x1, d$weight, d$group)
  base_summary <- group_summary_base(d)
  base_mean <- group_mean_base(d)
  base_keys <- key_index_base(d)
  base_q <- quantiles_base(d$x1, d$group)
  base_agg <- aggregate_mean_dplyr_reference(d)

  results[[length(results) + 1L]] <- run_case(
    paste(country, "weighted_mean_base"), d,
    weighted_mean_base(d$x1, d$weight, d$group),
    check = function(x) stopifnot(isTRUE(all.equal(x, base_wm)))
  )
  results[[length(results) + 1L]] <- run_case(
    paste(country, "aggregate_mean_base"), d,
    aggregate_mean_base(d),
    check = function(x) stopifnot(isTRUE(all.equal(x, base_agg)))
  )
  results[[length(results) + 1L]] <- run_case(
    paste(country, "aggregate_mean_collapse"), d,
    aggregate_mean_collapse(d),
    check = function(x) {
      x <- x[order(x$group), , drop = FALSE]
      y <- base_agg[order(base_agg$group), , drop = FALSE]
      stopifnot(isTRUE(all.equal(x, y, tolerance = 1e-12, check.attributes = FALSE)))
    }
  )
  results[[length(results) + 1L]] <- run_case(
    paste(country, "weighted_mean_collapse"), d,
    weighted_mean_collapse(d$x1, d$weight, d$group),
    check = function(x) stopifnot(isTRUE(all.equal(x, base_wm, tolerance = 1e-12)))
  )
  results[[length(results) + 1L]] <- run_case(
    paste(country, "group_summary_base"), d,
    group_summary_base(d),
    check = function(x) stopifnot(isTRUE(all.equal(x, base_summary)))
  )
  results[[length(results) + 1L]] <- run_case(
    paste(country, "group_mean_base"), d,
    group_mean_base(d),
    check = function(x) stopifnot(isTRUE(all.equal(x, base_mean)))
  )
  results[[length(results) + 1L]] <- run_case(
    paste(country, "group_mean_collapse"), d,
    group_mean_collapse(d),
    check = function(x) {
      x <- x[order(x$group), , drop = FALSE]
      y <- base_mean[order(base_mean$group), , drop = FALSE]
      stopifnot(isTRUE(all.equal(x, y, tolerance = 1e-12, check.attributes = FALSE)))
    }
  )
  results[[length(results) + 1L]] <- run_case(
    paste(country, "key_index_base"), d,
    key_index_base(d),
    check = function(x) stopifnot(length(x) == length(base_keys))
  )
  results[[length(results) + 1L]] <- run_case(
    paste(country, "key_index_kit"), d,
    key_index_kit(d),
    check = function(x) stopifnot(length(x) == length(unique(paste(d$code, d$year, d$loc_id, sep = "\001"))))
  )
  results[[length(results) + 1L]] <- run_case(
    paste(country, "quantiles_base"), d,
    quantiles_base(d$x1, d$group),
    check = function(x) stopifnot(length(x) == length(base_q))
  )
  results[[length(results) + 1L]] <- run_case(
    paste(country, "quantiles_collapse"), d,
    quantiles_collapse(d$x1, d$group),
    check = function(x) stopifnot(length(x) == length(base_q))
  )
}

out <- do.call(rbind, results)
print(out, row.names = FALSE)
write.csv(out, file.path("dev", "outputs", "collapse-kit-benchmark.csv"), row.names = FALSE)
