# Batch runner: Step 3 policies per policy_id (split from test-batch-pipeline.R so files run in parallel).

skip_if_not_installed("targets")
skip_if_not_installed("arrow")
skip_if_not_installed("yaml")

# Step 3 policy ----

# One fit and one simulation, crossed with policy profiles.
make_policy_grid <- function(policies) {
  c(
    "seed: 7",
    "weather:",
    "  hist_years: [2017, 2019]",
    "model:",
    "  covariates: {method: user, vars: [hhsize, urban, electricity]}",
    "sim:",
    "  hist_years: [2018, 2019]",
    "  future_periods: [[2025, 2030]]",
    "  ssps: [ssp3_7_0]",
    "profiles:",
    "  weather:",
    "    tx_3m: {tx: {ref_period: [1, 3], form: continuous}}",
    "  policy:",
    paste0("    ", names(policies), ": ", unlist(policies)),
    "axes:",
    "  country: [TST]",
    "  weather: [tx_3m]",
    paste0("  policy: [", paste(names(policies), collapse = ", "), "]")
  )
}
policy_profiles <- list(
  none = "{}",
  cash = "{sp: {transfer_amount_usd: 60, targeting: exante_poor, targeting_threshold_pct: 30}}",
  mixed = "{sp: {transfer_amount_usd: 60, targeting: exante_poor, targeting_threshold_pct: 30}, infra: {elec_pct: 40}}"
)

policy_progress <- function(dir) {
  p <- withr::with_dir(dir, targets::tar_progress_branches())
  p <- as.data.frame(p[p$name %in% c("fit_tables", "sim_tables", "policy_tables"), ])
  rownames(p) <- p$name
  p
}

test_that("policies run per policy_id on the stored Step 2 run, write the Step 3 tables and are reused", {
  skip_if_not_installed("qs2")
  data <- withr::local_tempdir()
  batch_fixture_tree(data, projections = TRUE)
  proj <- withr::local_tempdir()
  withr::local_envvar(WISEAPP_DATA_PATH = data)
  write_project(proj, make_policy_grid(policy_profiles))

  g <- wise_spec_expand(file.path(proj, "spec.yaml"))
  expect_identical(nrow(g), 3L)
  expect_identical(length(unique(g$sim_id)), 1L)
  expect_true(is.na(g$policy_id[g$policy == "none"]))
  expect_identical(length(unique(g$policy_id[g$policy != "none"])), 2L)

  make_it(proj)
  out <- file.path(proj, "results")
  expect_identical(nrow(arrow::read_parquet(file.path(out, "failures.parquet"))), 0L)
  p <- policy_progress(proj)
  expect_identical(p["fit_tables", "branches"], 1L)
  expect_identical(p["sim_tables", "branches"], 1L)
  expect_identical(p["policy_tables", "branches"], 2L)
  # The Step 2 run is kept for the policy branches.
  stored <- file.path(proj, "_targets", "user", "sims", paste0(g$sim_id[[1L]], ".qs2"))
  expect_true(file.exists(stored))

  runs <- arrow::read_parquet(file.path(out, "runs.parquet"))
  expect_true(all(c("policy_id", "policy_levers", "policy") %in% names(runs)))
  expect_identical(runs$policy_levers[runs$axis_policy == "mixed"], "infra,sp")
  expect_true(is.na(runs$policy[runs$axis_policy == "none"]))

  # The baseline arm is stored once; each policy adds its own rows.
  annual <- arrow::open_dataset(file.path(out, "tables", "annual")) |> dplyr::collect()
  expect_identical(
    names(annual)[names(annual) != "code"],
    c(
      "sim_id", "policy_id", "scenario", "metric", "member", "sim_year", "value", "sd",
      "sd_resid", "var_within", "var_across", "weighted"
    )
  )
  expect_setequal(annual$policy_id, c(NA, g$policy_id[g$policy != "none"]))
  base <- annual[is.na(annual$policy_id), ]
  cash_id <- g$policy_id[g$policy == "cash"]
  cash <- annual[!is.na(annual$policy_id) & annual$policy_id == cash_id, ]
  expect_identical(nrow(cash), nrow(base))
  expect_identical(cash$member, base$member)
  # A positive transfer to the poor raises the mean outcome in every year.
  key <- function(d) paste(d$scenario, d$member, d$sim_year, d$metric)
  b_mean <- base[base$metric == "mean", ]
  c_mean <- cash[cash$metric == "mean", ]
  expect_true(all(c_mean$value >= b_mean$value[match(key(c_mean), key(b_mean))]))
  expect_true(any(c_mean$value > b_mean$value[match(key(c_mean), key(b_mean))]))

  summ <- arrow::open_dataset(file.path(out, "tables", "summary")) |> dplyr::collect()
  expect_identical(
    names(summ)[names(summ) != "code"],
    c(
      "sim_id", "policy_id", "scenario", "metric", "section", "measure", "group", "return_period",
      "estimate", "lo", "hi", "n", "text"
    )
  )
  pol <- summ[!is.na(summ$policy_id) & summ$policy_id == cash_id, ]
  expect_true(all(c(
    "policy_expected", "policy_adverse", "policy_threshold", "policy_adverse_dot",
    "policy_headline", "policy_incidence"
  ) %in% pol$section))
  expect_true(all(is.na(summ$policy_id[summ$section == "expected"])))
  # The expected effect of the historical arm is the difference of the stored
  # annual means (one equal-model mean over the same years).
  eff <- pol[pol$section == "policy_expected" & pol$metric == "mean" & pol$measure == "effect" &
    pol$group == "intermodel" & pol$scenario == "Historical", ]
  h <- function(d) mean(d$value[d$scenario == "Historical" & d$metric == "mean"])
  expect_equal(eff$estimate, h(cash) - h(base), tolerance = 1e-10)

  dec <- arrow::open_dataset(file.path(out, "tables", "decomposition")) |> dplyr::collect()
  expect_identical(
    names(dec)[names(dec) != "code"],
    c(
      "sim_id", "policy_id", "source", "scenario", "member", "sim_year", "metric", "group",
      "channel", "value", "sum", "weight", "n_units"
    )
  )
  expect_setequal(unique(dec$policy_id), g$policy_id[g$policy != "none"])
  expect_setequal(unique(dec$source), c("compact", "metric"))
  expect_true(all(c("delta_total", "lvl_total") %in% dec$channel))
  expect_true(all(c("baseline", "policy", "main", "total") %in% dec$channel[dec$source == "metric"]))
  expect_true("mean" %in% dec$metric)
  # The total channel is the policy state minus the baseline state.
  m <- dec[dec$policy_id == cash_id & dec$source == "metric" & dec$metric == "mean" & dec$group == "all", ]
  wide <- tidyr::pivot_wider(m[c("scenario", "member", "sim_year", "channel", "value")], names_from = channel, values_from = value)
  expect_equal(wide$total, wide$policy - wide$baseline, tolerance = 1e-8)

  meas <- arrow::open_dataset(file.path(out, "tables", "policy_measures")) |> dplyr::collect()
  expect_identical(
    names(meas)[names(meas) != "code"],
    c("sim_id", "policy_id", "section", "scenario", "metric", "measure", "group", "value", "text")
  )
  expect_true(all(c("transfer", "sp_effectiveness", "components", "treatment", "reach") %in% meas$section))
  expect_true("input_diagnostics" %in% meas$section[meas$policy_id == g$policy_id[g$policy == "mixed"]])
  expect_identical(unique(meas$code), "TST")

  prov <- arrow::read_parquet(file.path(out, "provenance.parquet"))
  expect_setequal(prov$stage, c("data", "weather", "fit", "sim", "policy"))
  manifest <- jsonlite::read_json(file.path(out, "manifest.json"))
  expect_true(all(c("decomposition", "policy_measures") %in% unlist(manifest$tables)))
  expect_identical(manifest$n_policies, 2L)

  # A second run recomputes nothing.
  make_it(proj)
  p <- policy_progress(proj)
  expect_identical(p$skipped, p$branches)

  # A new policy profile reruns only its policy branch.
  write_project(proj, make_policy_grid(c(policy_profiles, list(
    cash100 = "{sp: {transfer_amount_usd: 100, targeting: exante_poor, targeting_threshold_pct: 30}}"
  ))))
  make_it(proj)
  p <- policy_progress(proj)
  expect_identical(p["policy_tables", "branches"], 3L)
  expect_identical(p["policy_tables", "completed"], 1L)
  expect_identical(p["policy_tables", "skipped"], 2L)
  expect_identical(p["sim_tables", "skipped"], 1L)
  expect_identical(p["fit_tables", "skipped"], 1L)
  annual <- arrow::open_dataset(file.path(out, "tables", "annual")) |> dplyr::collect()
  expect_identical(length(unique(annual$policy_id[!is.na(annual$policy_id)])), 3L)
  # A transfer set from a welfare percentile reruns only its branch and records the amount used.
  pct_profile <- paste0(
    "{sp: {transfer_amount_mode: pctile, transfer_pctile: 10, transfer_n_payments: 6, ",
    "targeting: exante_poor, targeting_threshold_pct: 30}}"
  )
  write_project(proj, make_policy_grid(c(policy_profiles, list(
    cash100 = "{sp: {transfer_amount_usd: 100, targeting: exante_poor, targeting_threshold_pct: 30}}",
    p10 = pct_profile
  ))))
  make_it(proj)
  p <- policy_progress(proj)
  expect_identical(p["policy_tables", "branches"], 4L)
  expect_identical(p["policy_tables", "completed"], 1L)
  meas <- arrow::open_dataset(file.path(out, "tables", "policy_measures")) |> dplyr::collect()
  amt <- meas[meas$section == "transfer_amount", ]
  expect_identical(length(unique(amt$policy_id)), 1L)
  val <- stats::setNames(amt$value, amt$measure)
  expect_identical(val[["percentile"]], 10)
  expect_equal(val[["per_payment"]] * 6, val[["per_year"]])
  expect_equal(val[["daily_value"]] * 365, val[["per_year"]])
  expect_identical(unique(amt$text), "PPP")
  # Dropping the policies from the grid removes the stored Step 2 run.
  write_project(proj, make_policy_grid(list(none = "{}")))
  make_it(proj)
  expect_false(file.exists(stored))
  annual <- arrow::open_dataset(file.path(out, "tables", "annual")) |> dplyr::collect()
  expect_true(all(is.na(annual$policy_id)))
})

test_that("a shock-responsive policy stores its member-year rows and its program measures", {
  skip_if_not_installed("qs2")
  data <- withr::local_tempdir()
  batch_fixture_tree(data, projections = TRUE)
  proj <- withr::local_tempdir()
  withr::local_envvar(WISEAPP_DATA_PATH = data)
  write_project(proj, make_policy_grid(list(shock = paste0(
    "{sp: {sp_type: shock, trigger_variable: tx, trigger_type: weather, trigger_value: 29.5, ",
    "trigger_direction: above, transfer_amount_usd: 60, targeting: exante_poor, ",
    "targeting_threshold_pct: 40, loss_event_pct: 5}}"
  ))), keep = FALSE)
  make_it(proj)
  out <- file.path(proj, "results")
  expect_identical(nrow(arrow::read_parquet(file.path(out, "failures.parquet"))), 0L)
  annual <- arrow::open_dataset(file.path(out, "tables", "annual")) |> dplyr::collect()
  shock <- annual[grepl("^shock_", annual$metric), ]
  expect_true(all(c(
    "shock_activated", "shock_exposed_share", "shock_transfer_cost", "shock_admin_cost"
  ) %in% shock$metric))
  expect_false(anyNA(shock$policy_id))
  expect_true(all(shock$value[shock$metric == "shock_activated"] %in% c(0, 1)))
  expect_true(all(shock$value[shock$metric == "shock_transfer_cost"] >= 0))
  # One row per member and year, as the climate-member rows of the other metrics.
  n_mean <- sum(annual$metric == "mean" & !is.na(annual$policy_id))
  expect_identical(sum(shock$metric == "shock_activated"), n_mean)
  meas <- arrow::open_dataset(file.path(out, "tables", "policy_measures")) |> dplyr::collect()
  expect_true(all(c("shock_summary", "shock_climate_cost") %in% meas$section))
  af <- meas$value[meas$section == "shock_summary" & meas$measure == "activation_freq"]
  expect_true(all(af >= 0 & af <= 1))
  # The stored per-year rows give the summary: activation frequency by scenario.
  act <- shock[shock$metric == "shock_activated", ]
  freq <- vapply(split(act$value, act$scenario), mean, 0)
  sc <- meas$scenario[meas$section == "shock_summary" & meas$measure == "activation_freq"]
  expect_equal(unname(freq[sc]), af, tolerance = 1e-12)
  # The Step 2 run was not kept (keep_step2 = FALSE).
  expect_length(list.files(file.path(proj, "_targets", "user", "sims")), 0L)
  # A policy-only change then needs the simulation target invalidated.
  write_project(proj, make_policy_grid(list(shock = paste0(
    "{sp: {sp_type: shock, trigger_variable: tx, trigger_type: weather, trigger_value: 31, ",
    "trigger_direction: above, transfer_amount_usd: 60, targeting: exante_poor, ",
    "targeting_threshold_pct: 40}}"
  ))), keep = FALSE)
  make_it(proj)
  f <- arrow::read_parquet(file.path(out, "failures.parquet"))
  expect_identical(nrow(f), 1L)
  expect_identical(f$stage, "policy")
  expect_match(f$message, "stored Step 2 run is missing|failed")
})
