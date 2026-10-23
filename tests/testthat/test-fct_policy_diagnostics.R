test_that("policy_decile_movement reports the weighted share moving over one decile (DOC-03)", {
  y <- seq(1, 100, length.out = 1000)
  ctx <- list(
    engine = "rif", F_hat = stats::ecdf(y), y_baseline = y,
    delta_main = c(rep(50, 200), rep(0, 800)),
    svy_baseline = data.frame(weight = rep(1, 1000))
  )
  mv <- policy_decile_movement(ctx)
  # The bottom 200 households (deciles 1-2) move to 51-70 (deciles 5-7)
  expect_equal(mv$share, 0.2, tolerance = 0.01)
  expect_gte(mv$share_any, mv$share)

  ctx$delta_main <- rep(0, 1000)
  expect_equal(policy_decile_movement(ctx)$share, 0)

  # weights change the share
  ctx$delta_main <- c(rep(60, 100), rep(0, 900))
  ctx$svy_baseline$weight <- c(rep(5, 100), rep(1, 900))
  expect_equal(policy_decile_movement(ctx)$share, 500 / 1400, tolerance = 0.01)

  expect_null(policy_decile_movement(NULL))
  ctx$engine <- "fixest"
  expect_null(policy_decile_movement(ctx))
})
