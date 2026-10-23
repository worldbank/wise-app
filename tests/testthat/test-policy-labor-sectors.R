library(testthat)

# R2-BUG-05: sector reallocation runs only when a sector target was changed.

make_labor_fixture <- function(n = 600L, seed = 5L) {
  set.seed(seed)
  status <- sample(c("employed", "selfemployed", "unemployed"), n,
                   replace = TRUE, prob = c(0.5, 0.3, 0.2))
  sector <- sample(c("agriculture", "industry", "services"), n,
                   replace = TRUE, prob = c(0.4, 0.3, 0.3))
  working <- status != "unemployed"
  data.frame(
    welfare = stats::runif(n, 1, 5),
    weight = stats::runif(n, 0.5, 2),
    employed = as.integer(status == "employed"),
    selfemployed = as.integer(status == "selfemployed"),
    unemployed = as.integer(status == "unemployed"),
    agriculture = as.integer(working & sector == "agriculture"),
    industry = as.integer(working & sector == "industry"),
    services = as.integer(working & sector == "services")
  )
}

labor_vars <- c("employed", "selfemployed", "unemployed",
                "agriculture", "industry", "services")
sector_counts <- function(svy) {
  colSums(svy[c("agriculture", "industry", "services")])
}

test_that("employment-only change leaves sector counts unchanged", {
  svy <- make_labor_fixture()
  out <- apply_policy_to_svy(
    svy, labor = list(employment_change_pp = 5),
    model_vars = labor_vars, seed = 1L
  )
  expect_gt(sum(out$unemployed != svy$unemployed), 0)
  expect_identical(sector_counts(out), sector_counts(svy))
  # Reach counts only units whose employment status actually changed.
  reach <- policy_reach_mask(svy, out)
  expect_identical(sum(reach), sum(out$unemployed != svy$unemployed))
})

test_that("an unset sector target keeps that sector's count", {
  svy <- make_labor_fixture()
  out <- apply_policy_to_svy(
    svy, labor = list(sector_manufacturing = 50),
    model_vars = labor_vars, seed = 1L
  )
  working <- sum(svy$employed + svy$selfemployed)
  expect_identical(unname(sector_counts(out)[["services"]]),
                   unname(sector_counts(svy)[["services"]]))
  expect_equal(unname(sector_counts(out)[["industry"]]), round(working * 0.5))
})

test_that("an explicit 0% target is a change; NULL targets are not", {
  expect_true(has_labor_change(list(sector_manufacturing = 0)))
  expect_false(has_labor_change(list(
    employment_change_pp = 0,
    sector_manufacturing = NULL,
    sector_services = NULL
  )))
})

test_that("observed sector shares are weighted over the working population", {
  svy <- make_labor_fixture()
  shares <- .labor_sector_shares(svy)
  working <- svy$employed == 1L | svy$selfemployed == 1L
  w <- svy$weight
  expect_equal(
    shares[["industry"]],
    100 * sum(w[working & svy$industry == 1L]) / sum(w[working])
  )
  expect_equal(sum(shares), 100)
  expect_null(.labor_sector_shares(svy[c("welfare", "employed")]))
})

test_that("labour module reports sector targets only once moved", {
  svy <- make_labor_fixture()
  shares <- round(.labor_sector_shares(svy))
  shiny::testServer(
    mod_3_04_labor_server,
    args = list(
      selected_model = shiny::reactive(list(hh_covariates = labor_vars)),
      survey_data = shiny::reactive(svy)
    ),
    {
      session$setInputs(
        labor_emp = 3,
        sector_manufacturing = shares[["industry"]],
        sector_services = shares[["services"]]
      )
      sc <- session$returned$labor_scenario()
      expect_null(sc$sector_manufacturing)
      expect_null(sc$sector_services)
      expect_identical(sc$employment_change_pp, 3)

      session$setInputs(sector_services = shares[["services"]] + 10)
      sc <- session$returned$labor_scenario()
      expect_null(sc$sector_manufacturing)
      expect_equal(sc$sector_services, shares[["services"]] + 10)
    }
  )
})

# Survey layout of the GMD files: selfemployed is a subset of employed and is
# missing for people outside employment.
make_subset_fixture <- function(n = 2000L, seed = 8L) {
  set.seed(seed)
  status <- sample(c("wage", "self", "unemployed", "notinlf"), n,
                   replace = TRUE, prob = c(0.25, 0.3, 0.1, 0.35))
  emp <- status %in% c("wage", "self")
  sector <- sample(c("agriculture", "industry", "services"), n, replace = TRUE)
  data.frame(
    welfare = stats::runif(n, 1, 5),
    weight = 1,
    employed = as.integer(emp),
    unemployed = as.integer(status == "unemployed"),
    selfemployed = ifelse(emp, as.integer(status == "self"), NA_integer_),
    agriculture = ifelse(emp, as.integer(sector == "agriculture"), NA_integer_),
    industry = ifelse(emp, as.integer(sector == "industry"), NA_integer_),
    services = ifelse(emp, as.integer(sector == "services"), NA_integer_)
  )
}

test_that("the employment lever needs employed and unemployed only", {
  svy <- make_subset_fixture()
  # selfemployed and the sectors are not in the model
  out <- apply_policy_to_svy(
    svy, labor = list(employment_change_pp = 5),
    model_vars = c("employed", "unemployed"), seed = 1L
  )
  moved <- svy$unemployed == 1L & out$unemployed == 0L
  expect_gt(sum(moved), 0)
  expect_true(all(out$employed[moved] == 1L))
  expect_identical(out$selfemployed, svy$selfemployed)
  # without `unemployed` the lever cannot act
  none <- apply_policy_to_svy(
    svy, labor = list(employment_change_pp = 5),
    model_vars = c("employed", "selfemployed"), seed = 1L
  )
  expect_identical(none$employed, svy$employed)
})

test_that("new jobs keep selfemployed a subset of employed, in the observed share", {
  svy <- make_subset_fixture()
  out <- apply_policy_to_svy(
    svy, labor = list(employment_change_pp = 5),
    model_vars = c("employed", "selfemployed", "unemployed"), seed = 1L
  )
  moved <- svy$unemployed == 1L & out$unemployed == 0L
  expect_true(all(out$employed[moved] == 1L))
  expect_true(all(out$selfemployed[moved] %in% c(0L, 1L)))
  # no one is self-employed without being employed
  expect_true(all(out$employed[out$selfemployed %in% 1L] == 1L))
  expected <- mean(svy$selfemployed[svy$employed == 1L])
  expect_equal(mean(out$selfemployed[moved]), expected, tolerance = 0.08)
})

test_that("the sector lever runs without selfemployed", {
  svy <- make_subset_fixture()
  mv <- c("employed", "agriculture", "industry", "services")
  out <- apply_policy_to_svy(svy, labor = list(sector_manufacturing = 50), model_vars = mv, seed = 1L)
  working <- svy$employed == 1L
  expect_equal(mean(out$industry[working]), 0.5, tolerance = 0.01)
  expect_identical(is.na(out$industry), is.na(svy$industry))
  expect_false(is.null(.labor_sector_shares(svy[setdiff(names(svy), "selfemployed")])))
})

test_that("labour levers that cannot act are reported", {
  labor <- list(employment_change_pp = 2, sector_manufacturing = 40)
  expect_length(.labor_levers_unavailable(labor, names(make_subset_fixture()), labor_vars), 0L)
  r <- .labor_levers_unavailable(labor, names(make_subset_fixture()), c("selfemployed", "industry"))
  expect_match(r[["employment"]], "employed, unemployed not in the model")
  expect_match(r[["sectors"]], "employed, agriculture, services not in the model")
  r2 <- .labor_levers_unavailable(labor, c("welfare", "employed"), NULL)
  expect_match(r2[["employment"]], "unemployed not in the survey")
  # an unmoved lever is not reported
  expect_length(.labor_levers_unavailable(list(employment_change_pp = 0), "x", "y"), 0L)
})
