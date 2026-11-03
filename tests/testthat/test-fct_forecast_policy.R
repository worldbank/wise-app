policy_view_fixture <- function() {
  ref_b <- c(4.0, 4.1, 4.2, 4.3, 4.4)
  mem_b <- c(3.9, 4.15, 4.5)
  pl <- function(m, r) {
    out <- .forecast_placement_stats(m, r, "low")
    out$members$member <- paste0("m", seq_along(m))
    out$reference <- data.frame(year = 2001:2005, value = r)
    out
  }
  pb <- pl(mem_b, ref_b)
  pp <- pl(mem_b + 0.2, ref_b + 0.2)
  threshold <- pb$summary$reference_adverse_1in10
  list(
    baseline = pb, policy = pp, effect_members = rep(0.2, 3L), effect_reference = rep(0.2, 5L),
    summary = list(n_members = 3L, effect_member_median = 0.2, effect_reference_median = 0.2,
      share_worse_baseline = mean(mem_b <= threshold), share_worse_policy = mean(mem_b + 0.2 <= threshold),
      reference_adverse_1in10 = threshold),
    method = "mean", adverse_tail = "low"
  )
}

test_that("the policy text states the effect and the share of members below the fixed baseline level", {
  txt <- .forecast_policy_text(policy_view_fixture())
  expect_match(txt$headline, "Median member: \\+0\\.200 with the policy; median reference year: \\+0\\.200")
  expect_match(txt$tail, "33% without the policy, 0% with it")
  expect_match(txt$info, "not probabilities")
})

test_that("the policy chart has a baseline and a policy row for members and for reference years", {
  e <- echart_forecast_policy(policy_view_fixture(), "Mean")
  nm <- vapply(e$x$opts$series, function(s) s$name, "")
  expect_identical(nm, c("Reference years, baseline", "Reference years, policy",
    "Forecast members, baseline", "Forecast members, policy"))
  expect_identical(lengths(lapply(e$x$opts$series, `[[`, "data")), c(5L, 5L, 3L, 3L))
  expect_identical(class(echart_forecast_policy(NULL))[1L], class(echart_blank("x"))[1L])
})
