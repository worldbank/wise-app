# allocate_units_to_cells: population-weighted spread of sampled units onto
# the H3 cells each location covers, with an even-split fallback.

test_that("allocate_units_to_cells weights by pop_2020 and conserves totals", {
  cm <- data.frame(
    code = "BFA", year = 2018L, survname = "EHCVM",
    loc_id = c("L1", "L1", "L1", "L2"),
    h3 = c("a", "b", "c", "a"),
    pop_2020 = c(300, 100, NA, 50)
  )
  sd <- data.frame(
    code = "BFA", year = 2018L, survname = "EHCVM",
    loc_id = c("L1", "L1", "L2"),
    x = 1:3
  )

  out <- allocate_units_to_cells(cm, sd)

  # L1: 2 units over pops 300/100/0 (NA -> 0): a=1.5, b=0.5, c=0 (dropped)
  # L2: 1 unit, single cell: a=1
  expect_setequal(out$h3, c("a", "b"))
  expect_equal(out$n_units[out$h3 == "a"], 2.5)
  expect_equal(out$n_units[out$h3 == "b"], 0.5)
  expect_equal(sum(out$n_units), 3) # reconciles with the sample
})

test_that("allocate_units_to_cells falls back to an even split without weights", {
  cm <- data.frame(
    code = "BFA", year = 2018L, survname = "EHCVM",
    loc_id = c("L1", "L1", "L2", "L2"),
    h3 = c("a", "b", "c", "d"),
    pop_2020 = c(0, 0, NA, NA) # zero weights and no column value both fall back
  )
  sd <- data.frame(
    code = "BFA", year = 2018L, survname = "EHCVM",
    loc_id = c("L1", "L2", "L2"),
    x = 1:3
  )

  out <- allocate_units_to_cells(cm, sd)

  # L1: 1 unit over 2 cells, all-zero pops -> 0.5 each
  # L2: 2 units over 2 cells, NA pops -> 1 each
  expect_equal(out$n_units[out$h3 == "a"], 0.5)
  expect_equal(out$n_units[out$h3 == "b"], 0.5)
  expect_equal(out$n_units[out$h3 == "c"], 1)
  expect_equal(out$n_units[out$h3 == "d"], 1)
})

test_that("allocate_units_to_cells splits evenly when pop_2020 is absent", {
  cm <- data.frame(
    code = "BFA", year = 2018L, survname = "EHCVM",
    loc_id = c("L1", "L1"),
    h3 = c("a", "b")
  )
  sd <- data.frame(
    code = "BFA", year = 2018L, survname = "EHCVM",
    loc_id = c("L1", "L1", "L1"),
    x = 1:3
  )

  out <- allocate_units_to_cells(cm, sd)

  expect_equal(out$n_units[out$h3 == "a"], 1.5)
  expect_equal(out$n_units[out$h3 == "b"], 1.5)
})

test_that("allocate_units_to_cells returns NULL on unusable inputs", {
  cm <- data.frame(code = "BFA", year = 2018L, survname = "EHCVM",
                   loc_id = "L1", h3 = "a")
  sd <- data.frame(code = "BFA", year = 2018L, survname = "EHCVM",
                   loc_id = "L1")

  expect_null(allocate_units_to_cells(NULL, sd))
  expect_null(allocate_units_to_cells(cm, NULL))
  expect_null(allocate_units_to_cells(cm[, -5], sd)) # no h3 column
})

test_that("interview date summary reuses month and counts by wave", {
  df <- data.frame(
    economy = c("A", "A", "A", "A", "B"),
    year = c(2018L, 2018L, 2018L, 2021L, 2021L),
    countryyear = c("A, 2018", "A, 2018", "A, 2018", "A, 2021", "B, 2021"),
    timestamp = as.Date(c("2018-01-01", "2018-01-15", NA,
                          "2021-02-01", "2021-02-15")),
    month = c(1L, 1L, NA_integer_, 2L, 2L),
    stringsAsFactors = FALSE
  )

  out <- summarise_interview_dates(df)
  expect_equal(nrow(out), 3L)
  expect_equal(out$hh, c(2L, 1L, 1L))
  expect_equal(out$month_num, c(1L, 2L, 2L))
  expect_equal(as.character(out$countryyear),
               c("A, 2018", "A, 2021", "B, 2021"))
})

test_that("interview date plot variants return ggplot objects", {
  skip_if_not_installed("ggplot2")
  d <- data.frame(
    economy = rep("A", 4),
    countryyear = rep(c("A, 2018", "A, 2021"), each = 2),
    month_num = c(1L, 2L, 1L, 2L),
    hh = c(10L, 15L, 12L, 9L)
  )

  for (variant in c("grouped", "faceted", "heatmap")) {
    expect_s3_class(
      plot_interview_dates(d, variant = variant, unit_label = "Firms"),
      "ggplot"
    )
  }
  expect_equal(plot_interview_dates(d, unit_label = "Individuals")$labels$y,
               "Individuals")
  p <- plot_interview_dates(d, palette = "sequential")
  fill_scale <- p$scales$get_scales("fill")
  expect_equal(unname(fill_scale$palette(2)), c("#0071BC", "#00A6C7"))
  expect_equal(
    unname(plot_interview_dates(d[4:1, ], palette = "sequential")$scales$get_scales("fill")$palette(2)),
    c("#0071BC", "#00A6C7")
  )
  d_multi <- data.frame(
    economy = rep(c("Benin", "Burkina Faso"), each = 4),
    countryyear = rep(c("Benin, 2018", "Benin, 2021",
                        "Burkina Faso, 2018", "Burkina Faso, 2021"),
                      each = 2),
    month_num = rep(1:2, 4),
    hh = 1:8
  )
  p_multi <- plot_interview_dates(d_multi, palette = "sequential")
  multi_cols <- unname(p_multi$scales$get_scales("fill")$palette(4))
  expect_equal(multi_cols,
               c("#0071BC", "#00A6C7", "#8667B3", "#C28C2C"))
  expect_null(p_multi$scales$get_scales("fill")$name)
  expect_equal(p_multi$theme$text$size, 13)
  expect_null(plot_interview_dates(NULL))
})
