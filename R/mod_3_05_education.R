#' 3_05_education UI Function
#'
#' @description A shiny Module. Education scenario configuration - allows the
#'   user to define changes in educational attainment (primary, secondary and
#'   post-secondary completion) to be applied in the policy simulation. The
#'   levers are those of the `education` group of the variable list
#'   (`policy_registry()`); the controls are built in `mod_3_levers.R`.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_3_05_education_ui <- function(id) {
  mod_3_levers_ui(id)
}

#' 3_05_education Server Functions
#'
#' Manages education scenario inputs. Returns reactive scenario parameters to be
#' consumed by the policy simulation sub-module.
#'
#' @param id Module id.
#' @param selected_model Reactive named list of the selected model's parameters
#'   from Step 1. Used to determine which education variables are in the model
#'   and should be shown in the UI.
#' @param survey_data Reactive survey data frame, used to detect which education
#'   variables are present in the selected survey.
#' @param variable_list Reactive variable-list metadata data frame.
#'
#' @return A named list of reactives:
#'   \describe{
#'     \item{education_scenario}{Named list of education scenario parameters.}
#'   }
#'
#' @noRd
mod_3_05_education_server <- function(id,
                                      selected_model = reactive(NULL),
                                      survey_data = reactive(NULL),
                                      variable_list = reactive(NULL)) {
  moduleServer(id, function(input, output, session) {
    list(
      education_scenario = mod_3_levers_server(
        input, output, session,
        slot = "education", category = "education",
        selected_model = selected_model, survey_data = survey_data,
        variable_list = variable_list
      )
    )
  })
}
