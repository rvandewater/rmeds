# What MEDS-DEV offers, read in-process through reticulate. These calls are
# quick lookups, so unlike the pipeline steps they run inside the R session.

#' List MEDS-DEV tasks, models and datasets
#'
#' Reads MEDS-DEV's registries (`TASKS`, `MODELS`, `DATASETS`) from the
#' Python package in the rmeds environment.
#'
#' @return A sorted character vector of names.
#' @export
listMedsDevTasks <- function() {
  medsDevRegistry("TASKS")
}

#' @rdname listMedsDevTasks
#' @export
listMedsDevModels <- function() {
  medsDevRegistry("MODELS")
}

#' @rdname listMedsDevTasks
#' @export
listMedsDevDatasets <- function() {
  medsDevRegistry("DATASETS")
}

medsDevRegistry <- function(name) {
  medsDev <- reticulate::import("MEDS_DEV", convert = FALSE)
  registry <- reticulate::py_to_r(reticulate::py_get_attr(medsDev, name))
  sort(names(registry))
}
