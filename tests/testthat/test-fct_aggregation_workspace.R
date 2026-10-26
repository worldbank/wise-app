# Direct tests of the aggregation-workspace helpers moved out of
# mod_2_02_results_server(). Module-level cache behaviour is covered in
# test-mod_2_02_results.R.

.test_workspace <- function(max_entries = 3L) {
  cache_order <- new.env(parent = emptyenv())
  cache_order$keys <- character(0)
  cache_order$max_entries <- max_entries
  cache_order$hits <- 0L
  cache_order$misses <- 0L
  cache_order$evictions <- character(0)
  list(
    cache = new.env(parent = emptyenv()),
    cache_order = cache_order,
    prep_cache = .new_aggregation_preparation_cache(max_entries = 32L),
    weighted_suite_cache = new.env(parent = emptyenv())
  )
}

test_that(".cache_put evicts the least recently used key beyond max_entries", {
  ws <- .test_workspace(3L)
  for (k in c("a", "b", "c")) .cache_put(ws, k, k)
  expect_equal(ws$cache_order$keys, c("a", "b", "c"))
  expect_equal(.cache_get(ws, "a")$value, "a")
  .cache_put(ws, "d", "d")
  expect_equal(ws$cache_order$keys, c("c", "a", "d"))
  expect_equal(ws$cache_order$evictions, "b")
  expect_false(exists("b", envir = ws$cache, inherits = FALSE))
})

test_that(".cache_get counts hits and misses", {
  ws <- .test_workspace()
  miss <- .cache_get(ws, "x")
  expect_false(miss$found)
  expect_null(miss$value)
  .cache_put(ws, "x", 1)
  hit <- .cache_get(ws, "x")
  expect_true(hit$found)
  expect_equal(hit$value, 1)
  expect_equal(c(ws$cache_order$hits, ws$cache_order$misses), c(1L, 1L))
})

test_that("get_suite and assign_suite keep a bounded use-ordered suite cache", {
  ws <- .test_workspace()
  expect_null(get_suite(ws, "s0"))
  for (i in seq_len(.SUITE_CACHE_MAX + 2L)) assign_suite(ws, paste0("s", i), i)
  keys <- attr(ws$weighted_suite_cache, "keys")
  expect_length(keys, .SUITE_CACHE_MAX)
  expect_false(exists("s1", envir = ws$weighted_suite_cache, inherits = FALSE))
  expect_equal(get_suite(ws, "s3"), 3L)
  expect_equal(utils::tail(attr(ws$weighted_suite_cache, "keys"), 1L), "s3")
})

test_that(".aggregation_cache_snapshot reports entries and an empty snapshot for NULL", {
  empty <- .aggregation_cache_snapshot(NULL)
  expect_equal(empty$n_entries, 0L)
  expect_equal(empty$keys, character(0))
  ws <- .test_workspace()
  .cache_put(ws, "k1", 1:10)
  .cache_put(ws, "k2", "z")
  snap <- .aggregation_cache_snapshot(ws)
  expect_equal(snap$keys, c("k1", "k2"))
  expect_equal(snap$n_entries, 2L)
  expect_equal(snap$max_entries, 3L)
  expect_named(snap$entry_object_bytes, c("k1", "k2"))
  expect_gt(snap$object_bytes, 0)
  expect_false(is.na(snap$serialized_bytes))
})

test_that(".clear_workspace_cache empties every cache of the workspace", {
  ws <- .test_workspace()
  .cache_put(ws, "k", 1)
  .cache_get(ws, "k")
  assign_suite(ws, "s", 1)
  ws$prep_cache$entries <- list(a = 1)
  ws$prep_cache$keys <- "a"
  expect_null(.clear_workspace_cache(ws) |> invisible())
  expect_equal(ls(ws$cache, all.names = TRUE), character(0))
  expect_equal(ws$cache_order$keys, character(0))
  expect_equal(c(ws$cache_order$hits, ws$cache_order$misses), c(0L, 0L))
  expect_equal(ws$prep_cache$entries, list())
  expect_equal(ls(ws$weighted_suite_cache, all.names = TRUE), character(0))
  expect_equal(attr(ws$weighted_suite_cache, "keys"), character(0))
})

test_that(".pl_bw_key folds the poverty line and bandwidth into the key per method", {
  expect_equal(.pl_bw_key("mean", 3, 0.05), "")
  expect_equal(.pl_bw_key("gap", 3, 0.05), "_3")
  expect_equal(.pl_bw_key("fgt2", 2.15, 0.05), "_2.15")
  expect_equal(.pl_bw_key("headcount_ratio", 3, 0.05), "_3_0.05")
})

test_that("lazy aggregation lists build once, on first access", {
  calls <- 0L
  x <- .build_lazy_aggregation_method(function() {
    calls <<- calls + 1L
    list(mean = "table")
  }, "mean")
  expect_s3_class(x, "wise_lazy_aggregation_method_list")
  expect_equal(names(x), "mean")
  expect_equal(calls, 0L)
  expect_equal(x[["mean"]], "table")
  expect_equal(x$mean, "table")
  expect_equal(.lazy_aggregation_value(x), list(mean = "table"))
  expect_equal(.lazy_aggregation_table(x, "mean"), "table")
  expect_equal(calls, 1L)
  expect_equal(.lazy_aggregation_value("plain"), "plain")
})

test_that(".seeded_lazy is already built and never calls a builder", {
  x <- .seeded_lazy(data.frame(v = 1), "mean")
  expect_equal(x[["mean"]], data.frame(v = 1))
  expect_equal(.lazy_aggregation_table(x, "mean"), data.frame(v = 1))
})

test_that("builders return lazy weighted and unweighted slots without computing", {
  ws <- list(
    hs = list(pipeline = list(weight = NULL), so = list(transform = "none")),
    sc = list(), res = "original", skip = TRUE
  )
  bw_calls <- 0L
  bw <- function() {
    bw_calls <<- bw_calls + 1L
    0.05
  }
  hist <- .build_hist_for_method(ws, "mean", 3, bw, function() "mean", NULL)
  expect_named(hist, c("unweighted", "weighted"))
  expect_s3_class(hist$unweighted, "wise_lazy_aggregation_method_list")
  expect_equal(bw_calls, 0L)
  expect_null(.build_scn_for_method(ws, "mean", 3, bw, function() "mean"))
  ws$sc <- list(S1 = list(pipelines = list(m1 = list(weight = 1)), so = list(transform = "log")))
  scn <- .build_scn_for_method(ws, "mean", 3, bw, function() "mean")
  expect_named(scn, "S1")
  expect_named(scn$S1, c("unweighted", "weighted"))
  expect_equal(bw_calls, 0L)
})
