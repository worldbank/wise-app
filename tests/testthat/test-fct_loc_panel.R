test_that("loc_components numbers components by their first vertex", {
  # chain 1-2-3 (second edge reversed), cycle 4-5-6, duplicate 1-2 edges,
  # self-loop on 7, isolated 8
  panel <- loc_components(
    8L,
    from = c(1L, 3L, 4L, 5L, 6L, 2L, 1L, 7L),
    to   = c(2L, 2L, 5L, 6L, 4L, 1L, 2L, 7L)
  )
  expect_identical(panel, c(1L, 1L, 1L, 2L, 2L, 2L, 3L, 4L))
})

test_that("loc_components numbers by first vertex, not by first edge", {
  # 2, 5 and 6 are one component, but the first edge listed is 5-2
  panel <- loc_components(6L, from = c(5L, 2L), to = c(2L, 6L))
  expect_identical(panel, c(1L, 2L, 3L, 4L, 2L, 2L))
})

test_that("loc_components without edges gives one panel per location", {
  expect_identical(loc_components(3L, integer(0), integer(0)), 1:3)
})

test_that("loc_components follows long chains in both edge directions", {
  n <- 5000L
  forward <- loc_components(n, from = seq_len(n - 1L), to = seq(2L, n))
  backward <- loc_components(n, from = seq(2L, n), to = seq_len(n - 1L))
  expect_true(all(forward == 1L))
  expect_true(all(backward == 1L))
})

test_that("loc_components rejects NA endpoints", {
  expect_error(loc_components(2L, from = c(1L, NA), to = c(2L, 2L)),
    "known location ids")
})

test_that("loc_panel panel ids match the reference partition", {
  survey <- tibble::tribble(
    ~code, ~year, ~survname, ~loc_id, ~h3,  ~pop_2020,
    "AAA", 2020L, "S1",      1L,      "a",  100,
    "AAA", 2020L, "S1",      1L,      "b",  100,
    "AAA", 2020L, "S1",      2L,      "b",  100,
    "AAA", 2020L, "S1",      2L,      "c",  100,
    "AAA", 2020L, "S1",      3L,      "c",  100,
    "AAA", 2020L, "S1",      3L,      "d",  100,
    "AAA", 2020L, "S1",      4L,      "e",  100,
    "AAA", 2020L, "S1",      5L,      "f",  100,
    "AAA", 2020L, "S1",      6L,      "f",  100,
    "AAA", 2020L, "S1",      7L,      "g",  300,
    "AAA", 2020L, "S1",      7L,      "h",  100,
    "AAA", 2020L, "S1",      8L,      "h",  100,
    "AAA", 2020L, "S1",      8L,      "i",  100,
    "BBB", 2020L, "S2",      1L,      "a",  100,
    "BBB", 2020L, "S2",      2L,      "a",  100,
    "BBB", 2020L, "S2",      2L,      "z",  100
  )
  panel <- loc_panel(survey,
    id_col = loc_id, h3_col = h3, weight_col = pop_2020,
    group_cols = c("code", "year", "survname")
  )
  # Locations 1-3 chain through shared cells and 5-6 share cell f in full.
  # Location 7 holds a quarter of its weight in cell h, below the threshold, so
  # 7 stays alone and 8 (half in h) is not linked to it. Links ignore the survey
  # (cells are places), so BBB 1 and 2 join AAA 1 through cell a.
  expected <- tibble::tibble(
    code         = c(rep("AAA", 8), rep("BBB", 2)),
    year         = 2020L,
    survname     = c(rep("S1", 8), rep("S2", 2)),
    loc_id       = c(1:8, 1:2),
    loc_id_panel = c(1L, 1L, 1L, 2L, 3L, 3L, 4L, 5L, 1L, 1L)
  )
  expect_equal(panel, expected)
})
