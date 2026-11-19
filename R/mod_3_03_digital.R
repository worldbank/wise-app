#' 3_03_digital UI Function
#'
#' @description A shiny Module. Digital inclusion scenario configuration -
#'   allows the user to define changes in internet access and mobile phone
#'   ownership to be applied in the policy simulation. The levers are those of
#'   the `digital` group of the variable list (`policy_registry()`); the
#'   controls are built in `mod_3_levers.R`.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_3_03_digital_ui <- function(id) {
  mod_3_levers_ui(id)
}

#' 3_03_digital Server Functions
#'
#' Manages digital inclusion scenario inputs. Returns reactive scenario
#' parameters to be consumed by the policy simulation sub-module.
#'
#' @param id Module id.
#' @param selected_model Reactive named list of the selected model's parameters
#'   from Step 1. Used to determine which digital variables are in the model
#'   and should be shown in the UI.
#' @param survey_data Reactive survey data frame.
#' @param variable_list Reactive variable list; its `policy` columns decide the levers.
#'
#' @return A named list of reactives:
#'   \describe{
#'     \item{digital_scenario}{Named list of digital inclusion scenario parameters.}
#'   }
#'
#' @noRd
mod_3_03_digital_server <- function(id,
                                    selected_model = reactive(NULL),
                                    survey_data = reactive(NULL),
                                    variable_list = reactive(NULL)) {
  moduleServer(id, function(input, output, session) {
    list(
      digital_scenario = mod_3_levers_server(
        input, output, session,
        slot = "digital", category = "digital inclusion",
        selected_model = selected_model, survey_data = survey_data,
        variable_list = variable_list
      )
    )
  })
}
