# Policy lever registry ----
# Policy levers are found from the variable list, not from fixed variable
# names: a variable with a non-blank `policy` code is a lever (columns `policy`
# and `policy_group`, written by wise-app-data). The code is the identity of a
# lever everywhere (scenario key, control id, spec field stem); variable names
# are data. A lever is handled by its `type` (`logical`: binary access,
# `numeric` and `integer`: percent change) unless a special behaviour is
# registered for its code (`POLICY_SPECIAL_BEHAVIOURS`, which is code).
#
# Data directories without the `policy` columns (or with all of them blank)
# get the registry of the names the app used before (`POLICY_FALLBACK`).
# Pure and Shiny-free.

# Levers of data directories without policy metadata, in the order of the
# Model tab. `label` names the policy scenario, `control_label` and `icon`
# the Step 3 control; `level` is where the variable lives (hh/ind/firm/area).
#' @noRd
POLICY_FALLBACK <- data.frame(
  code = c(
    "electricity", "water", "sanitation", "health", "internet", "mobile",
    "piped", "piped_to_prem", "water_sanitation",
    "educ_primary", "educ_secondary", "educ_postsec",
    "employed", "selfemployed", "unemployed", "agriculture", "industry", "services"
  ),
  var = c(
    "electricity", "imp_wat_rec", "imp_san_rec", "ttime_health", "internet", "cellphone",
    "piped", "piped_to_prem", "imp_wat_san_rec",
    "educ_com1_hh", "educ_com2_hh", "educ_com3_hh",
    "employed", "selfemployed", "unemployed", "agriculture", "industry", "services"
  ),
  label = c(
    "Energy / Electricity access", "Improved water access", "Sanitation access",
    "Health access", "Internet access", "Mobile phone access", "Piped water access",
    "Piped water access (on premises)", "Improved water and sanitation access",
    "Educational attainment (primary)", "Educational attainment (secondary)",
    "Educational attainment (post-secondary)",
    "Employed", "Self employed", "Unemployed", "Agriculture", "Industry", "Services"
  ),
  control_label = c(
    "Access to electricity", "Access to improved water", "Access to improved sanitation",
    "Access to health facility", "Access to internet", "Mobile phone ownership",
    "Access to piped water", "Access to piped water (to premises)",
    "Access to improved water and sanitation",
    "Primary completion", "Secondary completion", "Post-secondary completion",
    "Employed", "Self employed", "Unemployed", "Agriculture", "Industry", "Services"
  ),
  icon = c(
    "fa-bolt", "fa-droplet", "fa-toilet", "fa-hospital", "fa-wifi", "fa-mobile-screen",
    "fa-tint", "fa-tint", "fa-tint",
    "fa-graduation-cap", "fa-graduation-cap", "fa-graduation-cap",
    "fa-briefcase", "fa-briefcase", "fa-briefcase", "fa-wheat-awn", "fa-industry", "fa-shop"
  ),
  group = c(
    rep("infrastructure", 4L), "digital", "digital",
    "infrastructure", "infrastructure", "infrastructure",
    "education", "education", "education",
    rep("labor", 6L)
  ),
  type = c(
    "logical", "logical", "logical", "numeric", "logical", "logical",
    "logical", "logical", "logical",
    "logical", "logical", "logical",
    rep("logical", 6L)
  ),
  level = c(
    "hh", "hh", "hh", "area", "hh", "hh",
    "hh", "hh", "hh",
    "hh", "hh", "hh",
    rep("ind", 6L)
  ),
  stringsAsFactors = FALSE
)

# Behaviours that differ from what the type would give. A special behaviour is
# code, not metadata: adding one is an app change.
#' @noRd
POLICY_SPECIAL_BEHAVIOURS <- c(
  health = "health",
  employed = "labor_emp", selfemployed = "labor_emp", unemployed = "labor_emp",
  agriculture = "labor_sector", industry = "labor_sector", services = "labor_sector"
)

# Groups with their own Step 3 module. Any other group, or none, is "other".
#' @noRd
POLICY_SLOTS <- c(
  infrastructure = "infra", digital = "digital", education = "education", labor = "labor"
)

# Scenario keys of earlier versions (batch specs, saved selections).
#' @noRd
POLICY_KEY_ALIASES <- c(
  A = "electricity", B = "water", C = "sanitation", D = "health", E = "internet",
  F = "mobile", G = "piped", H = "piped_to_prem", I = "water_sanitation",
  K = "educ_primary", L = "educ_secondary", M = "educ_postsec"
)

# Control-id stems of earlier versions (`<stem>_universal`, `<stem>_pct`).
#' @noRd
POLICY_STEM_ALIASES <- c(
  elec = "electricity", imp_wat_san = "water_sanitation",
  primary = "educ_primary", secondary = "educ_secondary", postsec = "educ_postsec"
)

# Variables the app derives when a data directory does not publish them.
# `combine = "and_one"` is a three-valued AND: 1 if all sources are 1, 0 if any
# source is 0 (even when another is missing), otherwise missing.
#' @noRd
POLICY_DERIVED <- list(
  imp_wat_san_rec = list(
    label = "Improved water and sanitation",
    sources = c("imp_wat_rec", "imp_san_rec"),
    combine = "and_one",
    role = "hh",
    policy = "water_sanitation",
    policy_group = "infrastructure"
  )
)

#' Behaviour of a lever
#' @param code Lever code(s).
#' @param type Variable type(s): `logical`, `integer` or `numeric`.
#' @return `health`, `labor_emp`, `labor_sector` (special), otherwise `binary`
#'   (logical) or `pct` (numeric).
#' @noRd
policy_behaviour <- function(code, type) {
  special <- unname(POLICY_SPECIAL_BEHAVIOURS[code])
  # the travel-time control needs a number; a binary `health` lever is generic
  special[code == "health" & type == "logical"] <- NA_character_
  ifelse(!is.na(special), special, ifelse(type %in% c("numeric", "integer"), "pct", "binary"))
}

#' Slot (Step 3 module) of a lever group
#' @noRd
policy_slot <- function(group) {
  group <- ifelse(is.na(group), "", as.character(group))
  slot <- unname(POLICY_SLOTS[group])
  ifelse(is.na(slot), "other", slot)
}

# The value of an optional text column as character, NA and "" alike "none".
#' @noRd
.policy_text <- function(x, n) {
  if (is.null(x)) {
    return(rep("", n))
  }
  x <- as.character(x)
  x[is.na(x)] <- ""
  trimws(x)
}

#' Lever registry
#'
#' One row per lever and level: the lever code, its variable, labels, group,
#' type, level and behaviour. Built from the `policy` and `policy_group`
#' columns of the variable list; without a lever there (column missing or all
#' blank) it is the table of the names the app used before.
#'
#' @param variable_list Variable list data frame, or `NULL`.
#' @return A data frame: `code`, `var`, `label` (policy scenario), `control_label`,
#'   `icon`, `group`, `slot`, `type`, `level`, `behaviour`.
#' @noRd
policy_registry <- function(variable_list = NULL) {
  fb <- POLICY_FALLBACK
  codes <- if (is.data.frame(variable_list) && nrow(variable_list)) {
    .policy_text(variable_list$policy, nrow(variable_list))
  } else {
    character(0)
  }
  if (!any(nzchar(codes))) {
    reg <- fb
  } else {
    vl <- variable_list[nzchar(codes), , drop = FALSE]
    n <- nrow(vl)
    level <- vapply(seq_len(n), function(i) {
      for (lvl in c("ind", "hh", "firm", "area")) {
        v <- if (lvl %in% names(vl)) vl[[lvl]][i] else NA
        if (!is.na(v) && v == 1L) {
          return(lvl)
        }
      }
      ""
    }, character(1))
    code <- codes[nzchar(codes)]
    label <- if ("label" %in% names(vl)) as.character(vl$label) else vl$name
    known <- match(code, fb$code)
    reg <- data.frame(
      code = code,
      var = as.character(vl$name),
      label = ifelse(is.na(known), label, fb$label[known]),
      control_label = ifelse(is.na(known), label, fb$control_label[known]),
      icon = ifelse(is.na(known), "fa-sliders", fb$icon[known]),
      group = .policy_text(vl$policy_group, n),
      type = if ("type" %in% names(vl)) as.character(vl$type) else "logical",
      level = level,
      stringsAsFactors = FALSE
    )
    # Known levers first, in the order of the Model tab; new ones as listed.
    reg <- reg[order(ifelse(is.na(known), Inf, known), seq_len(n)), , drop = FALSE]
  }
  reg$slot <- policy_slot(reg$group)
  reg$behaviour <- policy_behaviour(reg$code, reg$type)
  # The labour module controls the coupled labour levers and nothing else: they
  # belong to it whatever their group says, and other levers of the group are
  # generic ones.
  is_labor <- reg$behaviour %in% c("labor_emp", "labor_sector")
  reg$slot[is_labor] <- "labor"
  reg$slot[!is_labor & reg$slot == "labor"] <- "other"
  rownames(reg) <- NULL
  reg
}

#' Variables of a lever
#' @param registry Result of `policy_registry()`.
#' @param code Lever code(s).
#' @param level Optional level (`ind`, `hh`, `firm`, `area`).
#' @return Character vector of variable names.
#' @noRd
policy_lever_vars <- function(registry, code, level = NULL) {
  r <- registry[registry$code %in% code, , drop = FALSE]
  if (!is.null(level)) r <- r[r$level %in% level, , drop = FALSE]
  unique(r$var)
}

#' Policy scenario definitions for the Model tab
#'
#' A list keyed by lever code with the display `label` and the `vars` the policy
#' needs in the model (the variable at each level). Levers with a labour
#' behaviour are not Model-tab scenarios. The derived-variable spec of a lever
#' is attached as `derived` (`POLICY_DERIVED`).
#'
#' @param variable_list Variable list data frame, or `NULL` for the defaults.
#' @return A named list.
#' @noRd
policy_definitions <- function(variable_list = NULL) {
  reg <- policy_registry(variable_list)
  reg <- reg[!reg$behaviour %in% c("labor_emp", "labor_sector"), , drop = FALSE]
  out <- lapply(unique(reg$code), function(k) {
    r <- reg[reg$code == k, , drop = FALSE]
    def <- list(label = r$label[1L], vars = unique(r$var))
    der <- POLICY_DERIVED[vapply(POLICY_DERIVED, function(d) identical(d$policy, k), logical(1))]
    if (length(der)) def$derived <- der
    def
  })
  stats::setNames(out, unique(reg$code))
}

#' Predefined policy scenario definitions
#'
#' The definitions for a data directory without policy metadata, keyed by lever
#' code. Each entry maps a lever code to a human-readable label and a character
#' vector of variable names that the policy requires in the model. Data
#' directories whose variable list marks policy levers (`policy` column) use
#' `policy_definitions()` instead; earlier letter keys (`A` to `M`) are read as
#' lever codes (`POLICY_KEY_ALIASES`).
#'
#' @export
POLICY_DEFINITIONS <- policy_definitions(NULL)

#' Display label of a policy scenario
#'
#' The label of the definition, else the code with underscores as spaces.
#' @param code Lever code (or earlier letter key).
#' @param defs Policy definitions (`policy_definitions()`).
#' @noRd
policy_label <- function(code, defs = POLICY_DEFINITIONS) {
  code <- policy_normalise_keys(code)
  vapply(code, function(k) {
    lab <- defs[[k]]$label
    if (!is.null(lab) && nzchar(lab)) as.character(lab) else gsub("_", " ", k, fixed = TRUE)
  }, character(1), USE.NAMES = FALSE)
}

#' Lever codes of earlier scenario keys
#'
#' Letter keys (`A` to `M`) become lever codes; anything else is returned as
#' given.
#'
#' @param x Character vector of keys or codes.
#' @return Character vector of the same length.
#' @noRd
policy_normalise_keys <- function(x) {
  x <- as.character(x)
  hit <- x %in% names(POLICY_KEY_ALIASES)
  x[hit] <- unname(POLICY_KEY_ALIASES[x[hit]])
  x
}

#' Control ids of earlier versions as lever-code ids
#'
#' Renames `<stem>_universal` and `<stem>_pct` fields with an old stem
#' (`elec`, `imp_wat_san`, `primary`, `secondary`, `postsec`) to the lever code,
#' so saved and batch specs written before the codes round-trip.
#'
#' @param x Named list (or character vector of names) of control values.
#' @return `x` with the ids renamed.
#' @noRd
policy_normalise_stems <- function(x) {
  nm <- names(x)
  if (is.null(nm)) {
    return(x)
  }
  for (stem in names(POLICY_STEM_ALIASES)) {
    for (suffix in c("_universal", "_pct")) {
      nm[nm == paste0(stem, suffix)] <- paste0(POLICY_STEM_ALIASES[[stem]], suffix)
    }
  }
  names(x) <- nm
  x
}
