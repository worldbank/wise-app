# Shared by test-fct-results-echarts.R and test-fct_step1_headline.R

# RIF fit with a continuous weather variable moderated by a binary `urban`,
# plus the median sub-fit's coefficients and VCV for delta-method checks.
test_rif_moderated_fixture <- function() {
  set.seed(11)
  n <- 800
  df <- data.frame(temp = stats::rnorm(n, 3, 1), urban = stats::rbinom(n, 1, 0.5))
  df$welfare <- 1 - 0.3 * df$temp - 0.3 * df$temp * df$urban + stats::rnorm(n)
  sm <- build_selected_model(
    model_type = "Unconditional quantile regression (RIF)", engine = "rif",
    interactions = "urban", hh_covariates = "urban"
  )
  sw <- data.frame(name = "temp", cont_binned = "Continuous",
                   stringsAsFactors = FALSE)
  mf <- fit_model(df, list(name = "welfare", type = "numeric"), sw, sm)
  sub <- mf$fit3[[which(mf$taus == 0.5)]]
  t <- c("temp", "temp:urban")
  V <- .fixest_vcov(sub)[t, t]
  b <- stats::coef(sub)[t]
  # Effect b1 + v * b2 and its SE, with and without Cov(b1, b2).
  combo <- function(v, scale = 1) {
    w <- scale * c(1, v)
    list(
      est = sum(w * b),
      se = sqrt(as.numeric(t(w) %*% V %*% w)),
      se_indep = sqrt(sum(w^2 * diag(V)))
    )
  }
  list(df = df, mf = mf, combo = combo)
}
