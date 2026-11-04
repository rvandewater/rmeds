# The Python side of rmeds lives here and nowhere else: which distributions
# are pinned, which Python versions are allowed, which console scripts the
# pipeline may call, and where they are found.

pythonRequirements <- function() {
  c("OMOP_MEDS==0.4.0", "MEDS-DEV==0.1.0")
}

pythonVersionConstraint <- function() {
  ">=3.12,<3.14"
}

# Logical tool name -> console script installed by the pinned distributions.
pythonTools <- c(
  omopToMeds = "OMOP_MEDS",
  medsDevTask = "meds-dev-task",
  medsDevModel = "meds-dev-model",
  medsDevEvaluation = "meds-dev-evaluation"
)

declarePythonRequirements <- function() {
  reticulate::py_require(
    pythonRequirements(),
    python_version = pythonVersionConstraint()
  )
}

#' Set up the Python environment used by rmeds
#'
#' Declares the pinned `OMOP_MEDS` and `MEDS-DEV` requirements with
#' [reticulate::py_require()] and initialises Python, which makes reticulate
#' build (or reuse) a cached uv environment. Every pipeline step then runs the
#' console scripts of that one environment in a separate process. MEDS-DEV
#' builds a further, temporary environment per model on its own.
#'
#' Set the `rmeds.python` option to point at a pre-built environment instead
#' (for sites without internet access); set `UV_OFFLINE=1` to make reticulate
#' resolve from its cache only.
#'
#' @param check Check that every console script rmeds needs is installed.
#'
#' @return The path to the Python executable, invisibly.
#' @export
setupPythonEnvironment <- function(check = TRUE) {
  if (is.null(getOption("rmeds.python"))) {
    declarePythonRequirements()
  }
  python <- pythonExecutable()
  if (check) {
    missing <- names(pythonTools)[!vapply(names(pythonTools), toolExists, logical(1))]
    if (length(missing) > 0) {
      cli::cli_abort(c(
        "The Python environment at {.file {python}} lacks required tools.",
        x = "Missing: {.code {unname(pythonTools[missing])}}.",
        i = "Expected: {.code {pythonRequirements()}}."
      ))
    }
  }
  invisible(python)
}

#' Describe the Python environment used by rmeds
#'
#' @return A list with the Python executable and the installed versions of
#'   the pinned distributions (`NA` when not installed).
#' @export
pythonEnvironmentInfo <- function() {
  python <- pythonExecutable()
  distributions <- sub("==.*$", "", pythonRequirements())
  list(
    python = python,
    pythonVersion = as.character(reticulate::py_version()),
    packages = vapply(distributions, pythonPackageVersion, character(1))
  )
}

# py_config() initialises Python (building the py_require() env if needed);
# py_exe() alone returns NULL before initialisation.
pythonExecutable <- function() {
  getOption("rmeds.python", default = reticulate::py_config()$python)
}

pythonPackageVersion <- function(distribution) {
  metadata <- reticulate::import("importlib.metadata")
  tryCatch(metadata$version(distribution), error = function(e) NA_character_)
}

pythonToolCandidates <- function(tool) {
  script <- pythonTools[[tool]]
  file.path(dirname(pythonExecutable()), c(script, paste0(script, ".exe")))
}

toolExists <- function(tool) {
  any(file.exists(pythonToolCandidates(tool)))
}

pythonToolPath <- function(tool) {
  candidates <- pythonToolCandidates(tool)
  found <- candidates[file.exists(candidates)]
  if (length(found) == 0) {
    cli::cli_abort(c(
      "Cannot find the {.code {pythonTools[[tool]]}} console script.",
      i = "Run {.fn setupPythonEnvironment} first."
    ))
  }
  found[[1]]
}
