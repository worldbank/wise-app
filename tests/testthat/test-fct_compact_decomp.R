# Direct tests of the compact-decomposition helpers. The adverse-year and
# future-decomposition numbers are pinned in
# test-w3-b-future-decomposition-characterization.R.

.compact_rows <- function(scenario = "S", members = c("a", "b"), sums = c(a = 2, b = 4)) {
  channels <- c(.compact_decomp_channels, .compact_level_channels, "baseline_level")
  rows <- dplyr::bind_rows(lapply(members, function(m) {
    out <- data.frame(scenario = scenario, member = m, sim_year = c(2001L, 2002L))
    for (ch in channels) {
      out[[paste0("sum_", ch)]] <- sums[[m]]
      out[[paste0("weight_", ch)]] <- 1
    }
    out
  }))
  rows
}

test_that(".compact_member_mean pools years within a member, then averages members equally", {
  rows <- data.frame(member = c("a", "a", "b"), s = c(1, 3, 10), w = c(1, 1, 5))
  expect_equal(.compact_member_mean(rows, "s", "w"), mean(c(4 / 2, 10 / 5)))
  # Rows without a member column count as one member.
  expect_equal(.compact_member_mean(rows[, c("s", "w")], "s", "w"), 14 / 7)
  # Non-finite sums and non-positive weights are dropped; nothing left is NA.
  bad <- data.frame(member = "a", s = c(NA, 1), w = c(1, 0))
  expect_true(is.na(.compact_member_mean(bad, "s", "w")))
})

test_that(".compact_future_combine returns every channel and zero-fills optional ones", {
  rows <- .compact_rows()
  rows$sum_delta_sp_shock <- NULL
  rows$sum_lvl_sp_shock <- NULL
  out <- .compact_future_combine(rows)
  expect_named(out, c(.compact_decomp_channels, .compact_level_channels))
  expect_equal(out[["delta_total"]], 3)
  expect_equal(out[["delta_sp_shock"]], 0)
  expect_equal(out[["lvl_sp_shock"]], 0)
  expect_equal(.compact_future_combine(rows[0, ]), setNames(numeric(0), character(0)))
  expect_equal(.compact_future_combine(NULL), setNames(numeric(0), character(0)))
})

test_that(".decomp_scenario_rows selects a scenario from channel or decile summaries", {
  chan <- .compact_rows("S")
  other <- .compact_rows("T")
  x <- list(channel_summary = rbind(chan, other), decile_summary = chan[1:2, ])
  expect_equal(nrow(.decomp_scenario_rows(x, "S")), 4L)
  expect_equal(nrow(.decomp_scenario_rows(x, "T")), 4L)
  expect_equal(nrow(.decomp_scenario_rows(x, "S", decile = TRUE)), 2L)
  expect_equal(nrow(.decomp_scenario_rows(x, "T", decile = TRUE)), 0L)
})

test_that("scenario helpers recognise and list compact decomposition objects", {
  expect_false(.is_compact_decomp_scenarios(list()))
  expect_equal(.compact_future_scenarios(list()), character(0))
  chan <- .compact_rows("S")
  obj <- structure(list(channel_summary = chan), class = c("wise_compact_decomp_scenarios", "list"))
  expect_true(.is_compact_decomp_scenarios(obj))
  expect_equal(.compact_future_scenarios(obj), "S")
  obj$scenario_order <- c("T", "S")
  expect_equal(.compact_future_scenarios(obj), c("T", "S"))
})

test_that(".bind_compact_future_decompositions builds an empty shell and binds parts", {
  empty <- .bind_compact_future_decompositions(list(NULL), engine = NULL, is_rif = TRUE)
  expect_true(.is_compact_decomp_scenarios(empty))
  expect_equal(empty$engine, "rif")
  expect_true(empty$is_rif)
  expect_equal(empty$scenario_order, character(0))
  expect_equal(.bind_compact_future_decompositions(list())$engine, "fixest")

  part <- function(scenario) {
    chan <- .compact_rows(scenario)[1:2, ]
    chan$year_start <- 2001L
    chan$year_end <- 2002L
    chan$engine <- "fixest"
    chan$is_rif <- FALSE
    list(channel = chan, decile = chan, metadata = list(scenario = scenario), engine = "fixest")
  }
  bound <- .bind_compact_future_decompositions(list(part("S"), NULL, part("T")))
  expect_equal(bound$scenario_order, c("S", "T"))
  expect_equal(nrow(bound$channel_summary), 4L)
  expect_equal(nrow(bound$scenario_metadata), 2L)
  expect_equal(bound$engine, "fixest")
  expect_false(bound$is_rif)
})

test_that("adverse helpers rank within members and need support for every model", {
  welfare <- list(name = "welfare", type = "numeric")
  years <- 2001:2040
  rows <- dplyr::bind_rows(lapply(c("a", "b"), function(m) {
    out <- data.frame(scenario = "S", member = m, sim_year = years)
    for (ch in c(.compact_decomp_channels, .compact_level_channels, "baseline_level")) {
      out[[paste0("sum_", ch)]] <- if (ch == "baseline_level") as.numeric(years - 2000) else 1
      out[[paste0("weight_", ch)]] <- 1
    }
    out
  }))
  x <- list(channel_summary = rows)
  supports <- .decomp_adverse_supports(x, "S", "adverse_20", welfare)
  expect_named(supports, c("a", "b"))
  values <- .decomp_adverse_values(rows, supports)
  # 40 years at p = 0.05: rank 40 * 0.05 + 0.5 = 2.5 on baseline year - 2000.
  expect_equal(values[["baseline_level"]], 2.5)
  expect_equal(values[["delta_total"]], 1)
  expect_null(.decomp_adverse_values(rows, list()))
  # One model without enough years: no basis value.
  short <- rows[!(rows$member == "b" & rows$sim_year > 2010), ]
  short_support <- .decomp_adverse_supports(list(channel_summary = short), "S", "adverse_20", welfare)
  expect_null(.decomp_adverse_values(short, short_support))
})
