test_that("policy runs reject forecast windows before annual exposure calculations", {
  expect_error(apply_policy_delta_to_baseline(
    svy_baseline = data.frame(hhid = 1L), svy_policy = data.frame(hhid = 1L),
    model_fit = list(engine = "fixest"), so = list(name = "welfare"), hist_sim_baseline = list(),
    saved_scenarios_baseline = list("Seasonal forecast / Nov 2026 (October 2026 run)" = list())
  ), "Rerun Step 2 with the seasonal forecast switched off", fixed = TRUE)
})

test_that(".apply_binary_access hits the weighted share asked for (DOC-13)", {
  set.seed(1)
  n <- 2000L
  x <- rep(0L, n)
  w <- ifelse(seq_len(n) %% 10L == 0L, 20, 1)
  moved <- .apply_binary_access(x, FALSE, 30, w)
  expect_equal(sum(w[moved == 1L]) / sum(w), 0.30, tolerance = 0.01)
  # a count draw would move 30% of the rows, with a different weighted share
  expect_equal(sum(moved == 1L), 600L, tolerance = 1)

  down <- .apply_binary_access(rep(1L, n), FALSE, -40, w)
  expect_equal(sum(w[down == 0L]) / sum(w), 0.40, tolerance = 0.01)
})

test_that(".apply_binary_access without usable weights keeps the row-count draw", {
  x <- rep(0L, 100L)
  set.seed(7)
  a <- .apply_binary_access(x, FALSE, 25)
  set.seed(7)
  b <- .apply_binary_access(x, FALSE, 25, NULL)
  expect_identical(a, b)
  expect_equal(sum(a), 25L)
  set.seed(7)
  expect_identical(which(a == 1L), sort(sample.int(100L, 25L)))
})

test_that(".pick_rows takes the rows closest to the target weight", {
  set.seed(3)
  w <- c(rep(1, 50), rep(10, 5))
  got <- .pick_rows(seq_along(w), n = 5L, target = 20, w = w)
  expect_lte(abs(sum(w[got]) - 20), 5)
  expect_length(.pick_rows(seq_along(w), 0L, 0, w), 0L)
})

test_that("employment change hits the weighted share of the population (DOC-13)", {
  set.seed(11)
  n <- 3000L
  unemployed <- as.integer(seq_len(n) %% 5L == 0L)
  svy <- data.frame(
    welfare = stats::runif(n, 1, 5),
    weight = ifelse(seq_len(n) %% 7L == 0L, 15, 1),
    employed = 1L - unemployed, selfemployed = 0L, unemployed = unemployed
  )
  out <- apply_policy_to_svy(
    svy, labor = list(employment_change_pp = 4),
    model_vars = c("employed", "selfemployed", "unemployed"), seed = 2L
  )
  moved <- svy$unemployed == 1L & out$unemployed == 0L
  expect_equal(sum(svy$weight[moved]) / sum(svy$weight), 0.04, tolerance = 0.003)
})
