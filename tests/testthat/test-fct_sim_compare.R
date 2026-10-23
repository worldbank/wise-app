

test_that("paired_effect_summary pools the coefficient error as the norm of the mean gradient", {
  eff <- tibble::tibble(
    sim_year = c(1L, 1L), model_id = c("a", "b"),
    baseline = 1, policy = 1.5, effect = 0.5, effect_sd = c(0.1, 0.1),
    effect_gradient = list(c(0.1, 0), c(-0.1, 0))
  )
  out <- paired_effect_summary(eff, center = "equal_model_mean")
  # Members' gradients point opposite ways: shared coefficient error cancels
  expect_equal(out$coef_sd, 0)
  same <- eff
  same$effect_gradient <- list(c(0.1, 0), c(0.1, 0))
  expect_equal(paired_effect_summary(same, center = "equal_model_mean")$coef_sd, 0.1)
})
