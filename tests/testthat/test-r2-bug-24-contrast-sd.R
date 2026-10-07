test_that("paired_effect_summary fallback coefficient SD does not shrink with years", {
  eff <- tibble::tibble(
    sim_year = 1:4, model_id = "m", baseline = 1, policy = 2, effect = 1,
    effect_sd = 0.2
  )
  s <- paired_effect_summary(eff)
  expect_equal(s$coef_sd, 0.2)
  eff8 <- tibble::tibble(
    sim_year = 1:16, model_id = "m", baseline = 1, policy = 2, effect = 1,
    effect_sd = 0.2
  )
  expect_equal(paired_effect_summary(eff8)$coef_sd, 0.2)
})

test_that("single and multi per-year paths share the residual-mode fallback", {
  for (f in c("aggregate_pipeline_per_year", "aggregate_pipeline_per_year_multi")) {
    src <- paste(deparse(body(get(f, envir = asNamespace("wiseapp")))), collapse = "\n")
    expect_match(src, '!".resid" %in% names(train_aug)', fixed = TRUE, info = f)
  }
})
