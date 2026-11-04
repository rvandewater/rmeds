#' rmeds: OMOP CDM to MEDS and MEDS-DEV from R
#'
#' rmeds runs the pipeline below from R. Each step takes the previous step's
#' object *or* a path, so any step can be run on its own or swapped out.
#'
#' 1. [exportCdmToParquet()]: CDM tables from a database to Parquet
#'    ([omopSource()]).
#' 2. [runMappingPreflight()]: aggregate mapping-quality report
#'    (`mappingPreflight`).
#' 3. [runOmopToMeds()]: OMOP to MEDS with `OMOP_MEDS` ([medsDataset()]).
#' 4. [extractTaskLabels()]: MEDS-DEV task labels ([medsLabels()]).
#' 5. [runMedsDevModel()]: train and predict ([medsModelRun()]).
#' 6. [evaluatePredictions()]: MEDS-DEV evaluation (`medsEvaluation`).
#' 7. [exportResults()]: shareable, small-cell-suppressed results.
#'
#' Python is managed in one place ([setupPythonEnvironment()]) and run in one
#' place ([runPythonTool()]); no step calls Python directly.
#'
#' @section Options:
#' * `rmeds.python`: path to a Python executable to use instead of the
#'   environment reticulate builds (for example a pre-built offline env).
#' * `rmeds.declare_python`: set to `FALSE` before loading to skip
#'   [reticulate::py_require()] on load.
#' * `rmeds.runner`: a function replacing the process runner (used in tests).
#' * `rmeds.verbose`: echo tool output to the console (default `TRUE`).
#'
#' @keywords internal
#' @importFrom rlang .data
"_PACKAGE"

# arrow translates these lubridate-style calls inside dplyr queries.
utils::globalVariables(c("hour", "minute", "second"))
