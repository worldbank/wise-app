#' 3_11_other UI Function
#'
#' @description A shiny Module. Policy levers of the variable list whose group
#'   has no module of its own (a new group, or a blank one). They are controlled
#'   like the other access levers and run with the infrastructure scenario
#'   (`step3_merge_access()`); the controls are built in `mod_3_levers.R`.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_3_11_other_ui <- function(id) {
  mod_3_levers_ui(id)
}

#' 3_11_other Server Functions
#'
#' @param id Module id.
#' @param selected_model Reactive named list of the selected model's parameters from Step 1.
#' @param survey_data Reactive survey data frame.
#' @param variable_list Reactive variable list; its `policy` columns decide the levers.
#'
#' @return A named list of reactives:
#'   \describe{
#'     \item{other_scenario}{Named list of the scenario parameters of the other levers.}
#'   }
#'
#' @noRd
mod_3_11_other_server <- function(id,
                                  selected_model = reactive(NULL),
                                  survey_data = reactive(NULL),
                                  variable_list = reactive(NULL)) {
  moduleServer(id, function(input, output, session) {
    list(
      other_scenario = mod_3_levers_server(
        input, output, session,
        slot = "other", category = "other policy",
        selected_model = selected_model, survey_data = survey_data,
        variable_list = variable_list
      )
    )
  })
}
