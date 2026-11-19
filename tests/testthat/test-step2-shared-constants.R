# R2-PERF-01: household-constant vectors are written to the artifact once.

.shared_fixture <- function(n = 2000L, members = 5L) {
  ids <- seq_len(n)
  w <- seq(0.5, 2, length.out = n)
  years <- rep(2030:2031, each = n %/% 2L)
  mk <- function(i) list(
    y_point = as.numeric(ids) * i, F_loading = matrix(i, n, 2L),
    id_vec = ids, weight = w, svy_row_id = ids, sim_year = years,
    weather_exposure = list(schema = 2L, status = "ok", row_index = ids,
      prediction_row_id = ids, weather_columns = "t"),
    weather_raw = list(kind = "ref")
  )
  list(
    hist_sim_result = list(pipeline = mk(1), so = list(name = "welfare")),
    new_scenarios = list(
      a = list(pipelines = stats::setNames(lapply(seq_len(members), mk), paste0("m", seq_len(members)))),
      b = list(pipelines = list(m1 = mk(9)))
    ),
    .run = list(id = "x", schema = 1L), .sig = "sig"
  )
}

test_that("sharing and unsharing round-trips bit-identically", {
  res <- .shared_fixture()
  shared <- step2_share_constants(res)
  expect_length(shared$.shared_constants, 3L) # ids, weights, years
  expect_s3_class(shared$new_scenarios$a$pipelines$m2$id_vec, "wiseapp_shared_ref")
  expect_s3_class(shared$new_scenarios$a$pipelines$m2$weather_exposure$row_index,
    "wiseapp_shared_ref")
  expect_identical(step2_unshare_constants(shared), res)
  # Through a real serialisation round trip as well.
  copy <- unserialize(serialize(shared, NULL))
  expect_identical(step2_unshare_constants(copy), res)
})

test_that("sharing shrinks the serialised result and leaves unrelated results alone", {
  res <- .shared_fixture(n = 20000L, members = 12L)
  expect_lt(length(serialize(step2_share_constants(res), NULL)),
    0.7 * length(serialize(res, NULL)))
  small <- list(hist_sim_result = list(pipeline = list(id_vec = 1:5)), new_scenarios = NULL)
  expect_identical(step2_unshare_constants(step2_share_constants(small))$new_scenarios, NULL)
  expect_identical(step2_unshare_constants(list(a = 1)), list(a = 1))
})
