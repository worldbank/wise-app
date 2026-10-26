# Monte Carlo check of the RIF coefficient bands (methodology review MR-12).
#
# Draws the coefficients of the nine quantile equations from the stored joint
# covariance, reruns the baseline arm (predict_rif) and the cash-transfer policy
# arm (annual channels) on a synthetic fixture, and compares the spread of the
# mean welfare of each arm and of the policy effect with the delta-method SD
# (aggregate_with_uncertainty_delta). With the covariance scaled down the two
# must agree (linear regime); at scale 1 the gap is the nonlinearity of the
# repositioning term. Usage: Rscript dev/mc_rif_policy_effect.R <draws> <scale>
# Prints one line: scale, MC SD / (scale * delta SD) for the baseline arm, the
# policy arm and the policy effect, and the shift of the mean effect in SDs.

suppressMessages({devtools::load_all(".", quiet = TRUE)})
source("tests/testthat/helper-policy-exposure.R")
args <- commandArgs(TRUE); B <- as.integer(args[1] %||% "300"); sc <- as.numeric(args[2] %||% "1")
set.seed(2610)
n <- 600L
baseline <- data.frame(
  code = "BFA", year = "2018", survname = "w", loc_id = seq_len(n), int_month = 1L,
  loc_id_panel = rep(1:150, length.out = n),
  temp = rnorm(n, 30, 2), electricity = rbinom(n, 1, 0.4), weight = 1
)
baseline$welfare <- exp(1 - 0.06 * baseline$temp + 0.5 * baseline$electricity + rnorm(n, 0, 0.5) + 1.8)
so <- list(name = "welfare", type = "numeric", transform = "log")
sw <- data.frame(name = "temp", cont_binned = "Continuous", stringsAsFactors = FALSE)
sm <- build_selected_model(
  model_type = "Unconditional quantile regression (RIF)", engine = "rif", cluster = "loc_id_panel"
)
fit_df <- baseline; fit_df$welfare <- log(baseline$welfare)  # Step 1 fits on the model scale
mf <- suppressWarnings(fit_model(fit_df, so, sw, sm))
V <- attr(mf$fit3, "wise_joint_vcov"); stopifnot(!is.null(V))
taus <- mf$taus; K <- length(taus)
baseline$.svy_row_id <- seq_len(n); scen <- baseline; scen$temp <- baseline$temp + 2
nm <- names(stats::coef(mf$fit3[[1]])); p <- length(nm)
cat("coefs:", nm, "\n")

# production-style chol_list (weather block active, joint factor)
chol_obj <- compute_chol_vcov(mf$fit3)
chol_obj <- suppressMessages(attach_active_mask(chol_obj, baseline, baseline, "temp", "original",
  svy_reference = baseline, outcome_col = "welfare"))
am <- attr(chol_obj, "active_mask")
cl <- lapply(chol_obj, function(x) x$L_active); attr(cl, "active_mask") <- am
attr(cl, "joint_L") <- rif_joint_factor(chol_obj, am)$L

pred <- function(fit, chol_list = NULL) predict_rif(fit_multi = fit, newdata = scen, svy = baseline,
  train_data = mf$train_data, taus = taus, outcome = "welfare", weather_cols = "temp", so = so, chol_list = chol_list)

policy <- baseline
poor <- baseline$welfare <= quantile(baseline$welfare, 0.3)
policy[[SP_TRANSFER_COL]] <- ifelse(poor, 0.3 * median(baseline$welfare), 0)
ids <- seq_len(n)
mk_pipe <- function(o) {
  p <- list(y_point = o$.fitted, svy_row_id = ids, sim_year = rep(2030L, n), weight = NULL, id_vec = ids)
  if (!is.null(attr(o, "F_loading"))) p$F_loading <- attr(o, "F_loading")
  .policy_test_attach_exposure(p, baseline, list(temp = scen$temp))
}
arm_policy <- function(mf_use, pipe) {
  ctx <- .build_decomposition_context(baseline, policy, mf_use, so, skip_coef = FALSE, run_identity = "mc")
  prep <- .prepare_policy_annual_channels(ctx, "mc")
  .apply_policy_annual_pipeline(pipe, prep, "mc", chunk_size = 1000L)$pipeline
}
mu_mean <- function(pp) {
  m <- exp(pp$y_point - (pp$sp_log %||% 0)) + (pp$sp_level %||% 0)
  mean(m)
}
# --- delta method ---
o0 <- pred(mf$fit3, cl); p0 <- mk_pipe(o0); pp0 <- arm_policy(mf, p0)
cat("F dims base/pol:", dim(p0$F_loading), dim(pp0$F_loading), "\n")
agg <- function(pp) aggregate_with_uncertainty_delta(pp$y_point, pp$F_loading, "mean", weights = rep(1, n),
  residuals = "none", train_aug = NULL, is_log = TRUE, sp_level = pp$sp_level, sp_log = pp$sp_log)
a0 <- agg(p0); a1 <- agg(pp0)
Fd <- a1$F_agg
Fb <- a0$F_agg
if (length(Fd) < length(Fb)) stop("dims")
Fb <- c(Fb, rep(0, length(Fd) - length(Fb)))
dm <- list(base_sd = sqrt(a0$var_coef), pol_sd = sqrt(a1$var_coef), effect_sd = sqrt(sum((Fd - Fb)^2)),
           effect = a1$value - a0$value)
print(dm)
# --- Monte Carlo over the joint covariance ---
Lv <- t(chol(V + diag(1e-12, nrow(V))))
beta_hat <- unlist(lapply(seq_len(K), function(k) stats::coef(mf$fit3[[k]])))
res <- matrix(NA_real_, B, 3, dimnames = list(NULL, c("base", "pol", "effect")))
for (b in seq_len(B)) {
  bs <- beta_hat + sc * as.numeric(Lv %*% rnorm(nrow(V)))
  fit_b <- mf$fit3
  grid_b <- mf$rif_grid
  for (k in seq_len(K)) {
    ix <- (k - 1L) * p + seq_len(p)
    fk <- fit_b[[k]]; fk$coefficients[] <- bs[ix]; fit_b[[k]] <- fk
    for (j in seq_len(p)) {
      hit <- grid_b$model == 3L & abs(grid_b$tau - taus[k]) < 1e-9 & grid_b$term == nm[j]
      grid_b$estimate[hit] <- bs[ix[j]]
    }
  }
  mf_b <- mf; mf_b$fit3 <- fit_b; mf_b$rif_grid <- grid_b
  ob <- pred(fit_b); pb <- mk_pipe(ob); ppb <- arm_policy(mf_b, pb)
  res[b, ] <- c(mean(exp(pb$y_point)), mu_mean(ppb), NA)
  res[b, 3] <- res[b, 2] - res[b, 1]
}
mc <- list(base_sd = sd(res[, "base"]), pol_sd = sd(res[, "pol"]), effect_sd = sd(res[, "effect"]),
           effect_mean = mean(res[, "effect"]))
print(mc)
cat("scale", sc, " ratio MC/(sc*delta) (base, policy, effect):",
  mc$base_sd / sc / dm$base_sd, mc$pol_sd / sc / dm$pol_sd, mc$effect_sd / sc / dm$effect_sd,
  " effect shift/sd:", (mc$effect_mean - dm$effect) / mc$effect_sd, "\n")
