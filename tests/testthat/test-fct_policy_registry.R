# Policy lever registry: levers come from the `policy` columns of the variable
# list, type decides behaviour, and old data directories / old specs keep working.

vl_levers <- function(extra = NULL) {
  base <- data.frame(
    name = c("elec_access", "internet", "income_idx", "clean_fuel", "ttime_health", "agecat"),
    label = c("Access to electricity", "Internet", "Income index", "Clean cooking fuel",
              "Travel time to clinic", "Age category"),
    type = c("logical", "logical", "numeric", "logical", "numeric", "factor"),
    ind = 0L, hh = c(1L, 1L, 1L, 1L, 0L, 0L), firm = 0L, area = c(0L, 0L, 0L, 0L, 1L, 0L),
    policy = c("electricity", "internet", "income", "clean_cooking", "health", ""),
    policy_group = c("infrastructure", "digital", "livelihoods", "", "infrastructure", ""),
    stringsAsFactors = FALSE
  )
  if (!is.null(extra)) base <- rbind(base, extra)
  base
}

test_that("without policy metadata the registry is the table of earlier names", {
  reg <- policy_registry(NULL)
  expect_identical(
    reg$code[reg$behaviour %in% c("binary", "pct", "health")],
    c("electricity", "water", "sanitation", "health", "internet", "mobile", "piped",
      "piped_to_prem", "water_sanitation", "educ_primary", "educ_secondary", "educ_postsec")
  )
  expect_identical(policy_lever_vars(reg, "water"), "imp_wat_rec")
  expect_identical(policy_lever_vars(reg, "mobile"), "cellphone")
  # missing column, or a column that is all blank: same table
  vl <- vl_levers()
  expect_identical(policy_registry(vl[setdiff(names(vl), c("policy", "policy_group"))]), reg)
  vl$policy <- ""
  expect_identical(policy_registry(vl), reg)
  vl$policy <- NA_character_
  expect_identical(policy_registry(vl), reg)
})

test_that("levers come from the policy column, whatever the variable is called", {
  reg <- policy_registry(vl_levers())
  expect_setequal(reg$code, c("electricity", "internet", "income", "clean_cooking", "health"))
  expect_identical(policy_lever_vars(reg, "electricity"), "elec_access")
  # known codes keep the Model-tab label, new ones the variable's label
  expect_identical(reg$label[reg$code == "electricity"], "Energy / Electricity access")
  expect_identical(reg$label[reg$code == "income"], "Income index")
  # known levers first, in the order of the Model tab, then new ones as listed
  expect_identical(reg$code, c("electricity", "health", "internet", "income", "clean_cooking"))
})

test_that("type decides behaviour; special behaviours are registered by code", {
  reg <- policy_registry(vl_levers())
  b <- stats::setNames(reg$behaviour, reg$code)
  expect_identical(b[["electricity"]], "binary")
  expect_identical(b[["clean_cooking"]], "binary")
  expect_identical(b[["income"]], "pct")
  expect_identical(b[["health"]], "health")
  expect_identical(policy_behaviour("employed", "logical"), "labor_emp")
  expect_identical(policy_behaviour("services", "logical"), "labor_sector")
})

test_that("the travel-time behaviour needs a numeric health variable", {
  expect_identical(policy_behaviour(c("health", "health"), c("numeric", "logical")), c("health", "binary"))
  vl <- vl_levers()
  vl$type[vl$policy == "health"] <- "logical"
  reg <- policy_registry(vl)
  expect_identical(reg$behaviour[reg$code == "health"], "binary")
  cfg <- wise_access_config(list(health_universal = TRUE), "infra", reg)
  svy <- data.frame(ttime_health = c(0L, 0L, 1L))
  expect_true(has_infra_change(cfg))
  expect_identical(apply_policy_to_svy(svy, infra = cfg)$ttime_health, c(1L, 1L, 1L))
})

test_that("the group decides the slot; blank or unknown groups are 'other'", {
  reg <- policy_registry(vl_levers())
  s <- stats::setNames(reg$slot, reg$code)
  expect_identical(s[["electricity"]], "infra")
  expect_identical(s[["internet"]], "digital")
  expect_identical(s[["income"]], "other")
  expect_identical(s[["clean_cooking"]], "other")
  expect_identical(policy_slot(c("education", "labor", "", NA, "whatever")),
                   c("education", "labor", "other", "other", "other"))
  # labour levers belong to the labour module; other levers of that group do not
  vl <- vl_levers(data.frame(
    name = c("employed", "union"), label = c("Employed", "Union"), type = "logical",
    ind = 1L, hh = 0L, firm = 0L, area = 0L,
    policy = c("employed", "union"), policy_group = c("misc", "labor")
  ))
  reg <- policy_registry(vl)
  expect_identical(reg$slot[reg$code == "employed"], "labor")
  expect_identical(reg$slot[reg$code == "union"], "other")
})

test_that("one code at two levels keeps both variables", {
  vl <- vl_levers(data.frame(
    name = "elec_ind", label = "Electricity (person)", type = "logical",
    ind = 1L, hh = 0L, firm = 0L, area = 0L, policy = "electricity", policy_group = "infrastructure"
  ))
  expect_identical(policy_lever_vars(policy_registry(vl), "electricity"), c("elec_access", "elec_ind"))
  expect_identical(policy_lever_vars(policy_registry(vl), "electricity", level = "ind"), "elec_ind")
})

test_that("policy definitions are keyed by lever code", {
  defs <- policy_definitions(NULL)
  expect_identical(names(defs)[1:3], c("electricity", "water", "sanitation"))
  expect_false(any(c("employed", "services") %in% names(defs)))
  expect_identical(defs$water$vars, "imp_wat_rec")
  expect_identical(names(POLICY_DEFINITIONS), names(defs))
  ch <- get_policy_choices(vl_levers())
  expect_identical(unname(ch[["Income index"]]), "income")
  expect_identical(unname(ch[["Energy / Electricity access"]]), "electricity")
  locked <- get_policy_locked_vars(c("income", "electricity"), vl_levers())
  expect_setequal(locked$hh, c("income_idx", "elec_access"))
})

test_that("earlier keys and stems are translated", {
  expect_identical(policy_normalise_keys(c("A", "I", "K", "income", "z")),
                   c("electricity", "water_sanitation", "educ_primary", "income", "z"))
  x <- policy_normalise_stems(list(elec_universal = TRUE, elec_pct = 3, imp_wat_san_pct = 4,
                                   primary_pct = 5, water_pct = 6, health_mode = "max"))
  expect_identical(names(x), c("electricity_universal", "electricity_pct", "water_sanitation_pct",
                               "educ_primary_pct", "water_pct", "health_mode"))
  expect_identical(get_policy_locked_vars("A", vl_levers()), get_policy_locked_vars("electricity", vl_levers()))
  expect_identical(policy_label("A"), "Energy / Electricity access")
  expect_identical(policy_label("clean_cooking"), "clean cooking")
})

test_that("an earlier configuration export is read under the lever codes", {
  cfg <- list(inputs = list(
    `step3-infra-elec_universal` = TRUE, `step3-infra-imp_wat_san_pct` = 20,
    `step3-infra-water_pct` = 5, `step3-digital-mobile_pct` = 1,
    `step3-education-primary_pct` = 10, `step3-other-primary_pct` = 3,
    `step3-sp-sp_type` = "regular", `step3-labor-labor_emp` = 2,
    `step1-model-selected_policies` = "A"
  ))
  out <- .config_lever_ids(cfg)
  expect_setequal(names(out$inputs), c(
    "step3-infra-electricity_universal", "step3-infra-water_sanitation_pct",
    "step3-infra-water_pct", "step3-digital-mobile_pct", "step3-education-educ_primary_pct",
    "step3-other-educ_primary_pct", "step3-sp-sp_type", "step3-labor-labor_emp",
    "step1-model-selected_policies"
  ))
  expect_identical(out$inputs[["step1-model-selected_policies"]], "electricity")
  expect_identical(.config_lever_ids(list(inputs = NULL)), list(inputs = NULL))
  # the same export, new and old ids, gives one spec
  new <- cfg
  names(new$inputs) <- names(out$inputs)
  new$inputs[["step1-model-selected_policies"]] <- "electricity"
  expect_identical(names(.config_lever_ids(new)$inputs), names(out$inputs))
})

test_that("the derived water and sanitation variable is a three-valued AND and never overwritten", {
  df <- data.frame(
    imp_wat_rec = c(1, 1, 0, 0, NA, 1, NA, NA),
    imp_san_rec = c(1, 0, 0, NA, 0, NA, 1, NA)
  )
  expect_identical(apply_policy_derivations(df)$imp_wat_san_rec, c(1L, 0L, 0L, 0L, 0L, NA, NA, NA))
  df$imp_wat_san_rec <- c(1, 1, 1, 1, 1, 1, 1, 1)
  expect_identical(apply_policy_derivations(df)$imp_wat_san_rec, rep(1, 8))
})

test_that("a published derived variable keeps its row; an unpublished one gets a lever row", {
  vl <- vl_levers()
  vl$interact <- 1L
  out <- add_derived_policy_vars_to_vl(vl)
  row <- out[out$name == "imp_wat_san_rec", ]
  expect_identical(row$policy, "water_sanitation")
  expect_identical(row$policy_group, "infrastructure")
  # a list that marks no levers is left unmarked (the registry falls back)
  vl2 <- vl
  vl2$policy <- ""
  expect_identical(add_derived_policy_vars_to_vl(vl2)$policy[nrow(vl2) + 1L], NA_character_)
  # a list that publishes the variable is unchanged
  vl3 <- rbind(vl, transform(vl[1, ], name = "imp_wat_san_rec"))
  expect_identical(add_derived_policy_vars_to_vl(vl3), vl3)
})

test_that("access scenarios are built per lever code and carry the lever variables", {
  reg <- policy_registry(vl_levers())
  infra <- wise_access_config(list(electricity_universal = TRUE, health_mode = "max"), "infra", reg)
  expect_true(infra$electricity_universal)
  expect_identical(infra$electricity_access_change_pct, 100L)
  expect_identical(infra$lever_vars$electricity, "elec_access")
  expect_identical(infra$lever_vars$health, "ttime_health")
  other <- wise_access_config(list(income_pct = 10, clean_cooking_pct = -5), "other", reg)
  expect_identical(other$income_value_change_pct, 10)
  expect_identical(other$clean_cooking_access_change_pct, -5)
  expect_identical(other$lever_groups$income, "livelihoods")
  merged <- step3_merge_access(infra, other)
  expect_identical(merged$lever_vars$income, "income_idx")
  expect_true(all(c("electricity_universal", "income_value_change_pct") %in% names(merged)))
  expect_identical(step3_merge_access(NULL, NULL), NULL)
  # earlier stems in the control values are read as the lever's
  old <- wise_infra_config(list(elec_universal = TRUE, imp_wat_san_pct = 20))
  expect_true(old$electricity_universal)
  expect_identical(old$water_sanitation_access_change_pct, 20)
})

test_that("levers of the list act on their variables: renamed, new binary, new numeric", {
  reg <- policy_registry(vl_levers())
  svy <- data.frame(
    elec_access = rep(c(0L, 1L), 50), clean_fuel = rep(0L, 100), income_idx = rep(10, 100),
    ttime_health = rep(60, 100)
  )
  cfg <- step3_merge_access(
    wise_access_config(list(electricity_pct = 50), "infra", reg),
    wise_access_config(list(clean_cooking_universal = TRUE, income_pct = 20), "other", reg)
  )
  expect_true(has_infra_change(cfg))
  out <- apply_policy_to_svy(svy, infra = cfg, seed = 11L)
  expect_equal(sum(out$elec_access), 50 + 25)
  expect_true(all(out$clean_fuel == 1L))
  expect_equal(unique(out$income_idx), 12)
  expect_equal(unique(out$ttime_health), 60)
  # gated by the model like any lever
  gated <- apply_policy_to_svy(svy, infra = cfg, model_vars = "clean_fuel", seed = 11L)
  expect_identical(gated$elec_access, svy$elec_access)
  expect_equal(unique(gated$income_idx), 10)
  expect_true(all(gated$clean_fuel == 1L))
  expect_setequal(.policy_candidate_cols(infra = cfg), c("elec_access", "clean_fuel", "income_idx"))
  # an unmoved list changes nothing
  expect_identical(apply_policy_to_svy(svy, infra = wise_access_config(list(), "infra", reg)), svy)
})

test_that("moved levers whose variable cannot be applied are reported", {
  reg <- policy_registry(vl_levers())
  cfg <- wise_access_config(list(electricity_pct = 10, internet_pct = 10), "infra", reg)
  cfg <- step3_merge_access(cfg, wise_access_config(list(internet_pct = 10), "digital", reg))
  svy_cols <- c("elec_access", "other")
  out <- .access_levers_unavailable(cfg, svy_cols, model_vars = "other")
  expect_identical(out[["electricity"]], "variable not in the model")
  expect_identical(out[["internet"]], "variable not in the survey")
})

test_that("the summary card names the group of a moved lever", {
  reg <- policy_registry(vl_levers())
  other <- wise_access_config(list(income_pct = 10), "other", reg)
  expect_identical(.access_active_labels(other, "Infrastructure"), "Livelihoods")
  infra <- wise_access_config(list(electricity_pct = 10), "infra", reg)
  expect_identical(.access_active_labels(infra, "Infrastructure"), "Infrastructure")
  expect_identical(.access_active_labels(list(elec_access_change_pct = 5), "Infrastructure"), "Infrastructure")
})

test_that("a lever of a type without a control is not controlled", {
  vl <- vl_levers()
  vl$policy[vl$name == "agecat"] <- "age_group"
  vl$policy_group[vl$name == "agecat"] <- "infrastructure"
  reg <- policy_registry(vl)
  expect_identical(reg$behaviour[reg$code == "age_group"], "none")
  expect_false("age_group_universal" %in% step3_ids("infra", reg))
  expect_false(any(grepl("^age_group", names(wise_access_config(list(), "infra", reg)))))
})

test_that("a lever on two variables has one control and keeps both variables", {
  vl <- vl_levers(data.frame(
    name = "elec_ind", label = "Electricity (person)", type = "logical", ind = 1L, hh = 0L,
    firm = 0L, area = 0L, policy = "electricity", policy_group = "infrastructure",
    stringsAsFactors = FALSE
  ))
  reg <- policy_registry(vl)
  cfg <- wise_access_config(list(electricity_universal = TRUE), "infra", reg)
  expect_identical(sum(names(cfg) == "electricity_universal"), 1L)
  expect_setequal(cfg$lever_vars$electricity, c("elec_access", "elec_ind"))
})

test_that("lever codes that cannot be input ids are ignored with a warning", {
  vl <- vl_levers()
  vl$policy[vl$name == "agecat"] <- "Foo-Bar"
  expect_warning(reg <- policy_registry(vl), "Foo-Bar")
  expect_false("Foo-Bar" %in% reg$code)
  expect_setequal(reg$code, c("electricity", "internet", "income", "clean_cooking", "health"))
})
