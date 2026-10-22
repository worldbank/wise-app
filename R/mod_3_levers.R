# Access-lever controls shared by the Step 3 modules ----
# The infrastructure, digital, education and other-policies modules
# (`mod_3_02` , `mod_3_03`, `mod_3_05`, `mod_3_11`) differ only in which levers
# of the registry (`policy_registry()`) they show. Controls are generated from
# the registry rows of the module's slot: binary levers get a "universal"
# toggle and a share slider, numeric levers a percent-change slider, and the
# health lever its travel-time control (`health` is the one special behaviour
# here). Input ids are `<code>_universal` and `<code>_pct`.

# Wording of the slider of a binary lever, by slot.
#' @noRd
.lever_words <- function(slot) {
  if (identical(slot, "education")) {
    list(
      label = "Share of unserved gaining attainment (%)",
      hint = paste(
        "Percentage of currently non-attaining households to give attainment",
        "(negative values remove attainment from currently-attaining households);",
        "not a percentage-point change in overall attainment."
      )
    )
  } else {
    list(
      label = "Share of unserved gaining access (%)",
      hint = paste(
        "Percentage of currently unserved households to give access",
        "(negative values remove access from currently-served households);",
        "not a percentage-point change in overall coverage."
      )
    )
  }
}

# Slider + universal toggle of a binary lever.
#' @noRd
.lever_access_ui <- function(ns, code, label, icon, slot) {
  words <- .lever_words(slot)
  tagList(
    tags$label(class = "control-label", tags$i(class = paste("fa", icon, "me-1")), label),
    checkboxInput(inputId = ns(paste0(code, "_universal")), label = "Universal", value = FALSE),
    conditionalPanel(
      condition = paste0("!input['", ns(paste0(code, "_universal")), "']"),
      sliderInput(
        inputId = ns(paste0(code, "_pct")), label = words$label,
        min = -20, max = 100, value = 0, step = 5, post = "%"
      ),
      tags$small(class = "text-muted d-block", words$hint)
    ),
    tags$hr(style = "margin: 8px 0;")
  )
}

# Percent-change slider of a numeric lever.
#' @noRd
.lever_pct_ui <- function(ns, code, label, icon) {
  tagList(
    tags$label(class = "control-label", tags$i(class = paste("fa", icon, "me-1")), label),
    sliderInput(
      inputId = ns(paste0(code, "_pct")), label = "Change in the value (%)",
      min = -100, max = 100, value = 0, step = 5, post = "%"
    ),
    tags$hr(style = "margin: 8px 0;")
  )
}

# Health facility access: reduce travel time by % OR cap at maximum minutes.
#' @noRd
.lever_health_ui <- function(ns, label, icon) {
  tagList(
    tags$label(class = "control-label", tags$i(class = paste("fa", icon, "me-1")), label),
    radioButtons(
      inputId = ns("health_mode"),
      label = shiny::tags$span(class = "visually-hidden", label),
      choices = c(
        "Reduce travel time by (%)" = "pct",
        "Set maximum travel time (min)" = "max"
      ),
      selected = "pct",
      inline = TRUE
    ),
    conditionalPanel(
      condition = paste0("input['", ns("health_mode"), "'] === 'pct'"),
      sliderInput(
        inputId = ns("health_travel_pct"), label = "Change travel time by (%)",
        min = -100, max = 20, value = 0, step = 5, post = "%"
      )
    ),
    conditionalPanel(
      condition = paste0("input['", ns("health_mode"), "'] === 'max'"),
      sliderInput(
        inputId = ns("health_travel_max"), label = "Maximum travel time (minutes)",
        min = 15, max = 240, value = 60, step = 15, post = " min"
      )
    )
  )
}

#' UI of an access-lever module
#' @param id Module id.
#' @noRd
mod_3_levers_ui <- function(id) {
  ns <- NS(id)
  tagList(
    uiOutput(ns("placeholder_ui")),
    uiOutput(ns("levers_ui"))
  )
}

#' Server logic of an access-lever module
#'
#' Registers the placeholder and control outputs on the calling module and
#' returns the scenario reactive. Call it inside `moduleServer()`.
#'
#' @param input,output,session The module's.
#' @param slot Registry slot: `infra`, `digital`, `education` or `other`.
#' @param category Name of the category in the messages (e.g. "infrastructure").
#' @param selected_model Reactive named list of the Step 1 model.
#' @param survey_data Reactive survey frame.
#' @param variable_list Reactive variable list (its `policy` columns decide the levers).
#' @return Reactive scenario list (`wise_access_config()`).
#' @noRd
mod_3_levers_server <- function(input, output, session, slot, category,
                                selected_model = reactive(NULL),
                                survey_data = reactive(NULL),
                                variable_list = reactive(NULL)) {
  ns <- session$ns

  # REACT-08: shared coefficient decomposition (utils_mod_1_helpers.R).
  coeffs <- model_coefficient_reactives(selected_model)$all

  registry <- reactive(policy_registry(variable_list()))
  slot_levers <- reactive({
    r <- registry()
    r[r$slot == slot & r$behaviour %in% c("binary", "pct", "health"), , drop = FALSE]
  })
  # levers whose variable is in the Step 1 model
  in_model <- reactive({
    r <- slot_levers()
    r[.lever_in_model(r$var, coeffs()), , drop = FALSE]
  })

  output$placeholder_ui <- renderUI({
    r <- slot_levers()
    if (nrow(r) == 0L) {
      return(if (identical(slot, "other")) {
        tags$small(class = "text-muted", "No other policy levers in the variable list.")
      })
    }
    if (nrow(in_model()) > 0L) {
      return(NULL)
    }
    svy <- survey_data()
    if (is.null(svy) || length(intersect(r$var, names(svy))) == 0L) {
      return(no_data_warning(paste0(
        "No ", category, " variables found in the selected survey (or level of analysis)."
      )))
    }
    cand <- policy_candidate_info(variable_list(), paste0("^", unique(r$var), "$"))
    policy_placeholder_tag(category, cand)
  })

  output$levers_ui <- renderUI({
    m <- in_model()
    # a lever whose variable the selected survey lacks cannot be controlled
    svy <- survey_data()
    if (!is.null(svy)) m <- m[m$var %in% names(svy), , drop = FALSE]
    if (nrow(m) == 0L && nrow(in_model()) == 0L) {
      return(NULL)
    }
    controls <- lapply(seq_len(nrow(m)), function(i) {
      switch(m$behaviour[i],
        binary = .lever_access_ui(ns, m$code[i], m$control_label[i], m$icon[i], slot),
        pct = .lever_pct_ui(ns, m$code[i], m$control_label[i], m$icon[i]),
        health = .lever_health_ui(ns, m$control_label[i], m$icon[i])
      )
    })
    # The section of other policies is titled by each lever's group text.
    if (identical(slot, "other")) {
      grp <- ifelse(nzchar(m$group), m$group, "other")
      controls <- unlist(lapply(unique(grp), function(g) {
        c(
          list(tags$h6(class = "mt-2", paste0(toupper(substring(g, 1, 1)), gsub("_", " ", substring(g, 2), fixed = TRUE)))),
          controls[grp == g]
        )
      }), recursive = FALSE)
    }
    # Levers of the slot that cannot be controlled, and why (not silently left out).
    r <- slot_levers()
    off <- r[!r$code %in% m$code, , drop = FALSE]
    svy <- survey_data()
    note <- if (nrow(off) > 0L) {
      reason <- vapply(off$var, function(v) {
        if (!is.null(svy) && !v %in% names(svy)) "variable not in the selected survey" else "variable not in the Step 1 model"
      }, character(1))
      tags$small(
        class = "text-muted d-block",
        "Not available: ",
        paste0(off$control_label, " (", reason, ")", collapse = "; ")
      )
    }
    tagList(controls, note)
  })
  shiny::outputOptions(output, "levers_ui", suspendWhenHidden = FALSE)

  reactive({
    reg <- registry()
    wise_access_config(
      step3_read_inputs(step3_ids(slot, reg), function(id) input[[id]]),
      slot, reg
    )
  })
}
