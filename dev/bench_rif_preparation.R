# Development-only benchmark for Step 1 multi-tau RIF preparation.
#
# Run from the repository root:
#   Rscript dev/bench_rif_preparation.R

pkgload::load_all(quiet = TRUE)

set.seed(20260911)
n <- as.integer(Sys.getenv("WISEAPP_RIF_BENCH_N", "300000"))
iterations <- as.integer(Sys.getenv("WISEAPP_RIF_BENCH_ITERATIONS", "15"))
taus <- seq(0.1, 0.9, by = 0.1)
y <- round(stats::rlnorm(n, meanlog = 2, sdlog = 0.7), 2)
if (n >= 1001L) y[c(17L, 101L, 1001L)] <- c(NA_real_, Inf, -Inf)

y_obs <- y[is.finite(y)]
bw <- tryCatch(stats::bw.SJ(y_obs),
               error = function(e) stats::bw.nrd0(y_obs))
dens <- stats::density(y_obs, bw = bw, n = 1024)

legacy <- function() {
  lapply(taus, function(tau) compute_rif(y, tau = tau, dens = dens))
}
precomputed <- function() compute_rif_multi(y, taus = taus, dens = dens)

stopifnot(identical(legacy(), precomputed()))

result <- bench::mark(
  repeated_single_tau = legacy(),
  precomputed_multi_tau = precomputed(),
  iterations = iterations,
  check = FALSE,
  memory = TRUE
)

print(result[, c("expression", "min", "median", "itr/sec", "mem_alloc", "gc/sec")])
