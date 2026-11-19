# Fixtures for the Step 2 input and table tests: a small compact Step 2 result
# (a historical run and two scenarios with weather-support summaries) in the
# shape `step2_compute()` publishes, so the Results module and the batch table
# builders can be fed the same object.

step2_fixture_pipe <- function(seed, years, centre, n_hh = 12L) {
  withr::with_seed(seed, {
    n <- n_hh * length(years)
    list(
      sim_year = rep(years, each = n_hh),
      y_point = log(centre) + stats::rnorm(n, 0, 0.25),
      weight = rep(c(1, 2, 3), length.out = n),
      F_loading = matrix(stats::rnorm(3L * n) * 0.02, nrow = n, ncol = 3L),
      train_aug = NULL, id_vec = rep(seq_len(n_hh), times = length(years)), id_col = NULL,
      svy_row_id = rep(seq_len(n_hh), times = length(years))
    )
  })
}

step2_fixture_outcome <- function() {
  list(type = "numeric", name = "welfare", transform = "log", units = "USD", povline = 3)
}

# The historical result of a run: weighted, a baseline survey of 12 households.
step2_fixture_hist <- function() {
  list(
    so = step2_fixture_outcome(), residuals = "none", has_weights = TRUE, seed = 123L,
    pipeline = step2_fixture_pipe(11L, 2000:2021, 4),
    svy = data.frame(welfare = 1:12, weight = rep(c(1, 2, 3), 4)),
    sim_summary = list(historical_years = c(2000L, 2021L), total_runs = 100L)
  )
}

# Two scenarios with three and two climate-model members.
step2_fixture_scenarios <- function() {
  mk <- function(base_seed, centres, label) {
    pipes <- lapply(seq_along(centres), function(i) {
      step2_fixture_pipe(base_seed + i, 2030:2050, centres[[i]])
    })
    names(pipes) <- paste0("model_", seq_along(centres))
    list(
      so = step2_fixture_outcome(), pipelines = pipes, n_models = length(centres),
      year_range = c("2030", "2050"),
      weather_support = data.frame(
        weather_variable = c("temp", "pr"), scenario = label, n_reference = 100L, n_scenario = 200L,
        robust_lo = c(1, 2), robust_hi = c(3, 4), reference_label = NA_character_,
        is_binned = FALSE, outside_n = c(5L, 20L), outside_share = c(0.025, 0.10),
        warning = c(FALSE, TRUE), warning_rule = "rule", n_members = length(centres),
        max_member_share = c(0.03, 0.2), stringsAsFactors = FALSE
      )
    )
  }
  list(
    "SSP2-4.5 / 2030-2050" = mk(100L, c(3.6, 3.9, 4.2), "SSP2-4.5 / 2030-2050"),
    "SSP5-8.5 / 2030-2050" = mk(200L, c(3.0, 3.3), "SSP5-8.5 / 2030-2050")
  )
}
