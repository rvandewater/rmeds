# Stage: evaluation with MEDS-DEV (MEDS-Evaluation). Produces medsEvaluation.

#' Evaluate predictions with MEDS-DEV
#'
#' Runs `meds-dev-evaluation` on a model run's held-out predictions and reads
#' the resulting JSON back as a tidy table of metrics. Only aggregate metrics
#' are returned.
#'
#' @param x A [medsModelRun()], or a path to a prediction Parquet file or a
#'   folder of them.
#' @param outputFolder Folder for the evaluation JSON. Defaults to
#'   `evaluation/` inside the model run.
#'
#' @return A `medsEvaluation` data frame with columns `metric` and `value`.
#' @export
evaluatePredictions <- function(x, outputFolder = NULL) {
  predictionsArg <- predictionsArgument(x)
  if (is.null(outputFolder)) {
    if (!inherits(x, "medsModelRun")) {
      cli::cli_abort("Give {.arg outputFolder} when {.arg x} is a path.")
    }
    outputFolder <- file.path(x$path, "evaluation")
  }
  outputFolder <- prepareOutputFolder(outputFolder)
  runPythonTool(
    "medsDevEvaluation",
    args = c(do.call(hydraOverrides, predictionsArg), hydraOverrides(output_dir = outputFolder)),
    logFile = file.path(outputFolder, ".rmeds", "meds-dev-evaluation.log")
  )
  evaluation <- readEvaluation(outputFolder)
  undefined <- evaluation$metric[is.na(evaluation$value)]
  if (length(undefined) > 0) {
    cli::cli_warn(c(
      "MEDS-Evaluation could not compute {.val {undefined}}.",
      i = "This usually means the evaluated labels hold only one class, common with few held-out subjects."
    ))
  }
  evaluation
}

# MEDS-Evaluation takes either one file/glob (predictions_path) or a folder
# whose every Parquet file is read (predictions_dir).
predictionsArgument <- function(x) {
  if (is.character(x) && length(x) == 1 && dir.exists(x)) {
    return(list(predictions_dir = normalizePath(x, winslash = "/")))
  }
  files <- if (inherits(x, "medsModelRun")) findPredictions(x) else normalizePath(x, winslash = "/", mustWork = TRUE)
  if (length(files) == 0) {
    cli::cli_abort("No prediction files found in {.file {x$path}}.")
  }
  if (length(files) == 1) {
    return(list(predictions_path = files))
  }
  folders <- unique(dirname(files))
  if (length(folders) > 1) {
    cli::cli_abort(c(
      "Predictions are spread over several folders: {.file {folders}}.",
      i = "Pass the folder or file to evaluate as {.arg x}."
    ))
  }
  list(predictions_path = file.path(folders, "*.parquet"))
}

#' Read MEDS-Evaluation results
#'
#' @param path Folder holding the evaluation JSON written by
#'   `meds-dev-evaluation`.
#'
#' @return A `medsEvaluation` data frame of numeric metrics, with nested JSON
#'   keys joined by `/` (e.g. `samples_equally_weighted/roc_auc_score`).
#'   Metrics MEDS-Evaluation could not compute (written as `NaN`, e.g. AUROC
#'   when the evaluated labels hold only one class) are `NA`.
#' @export
readEvaluation <- function(path) {
  path <- existingFolder(path, "Evaluation")
  files <- visibleFiles(path, "\\.json$")
  if (length(files) == 0) {
    cli::cli_abort("No evaluation JSON in {.file {path}}.")
  }
  metrics <- flattenMetrics(jsonlite::parse_json(readNonStandardJson(files[[1]])))
  structure(
    data.frame(metric = names(metrics), value = unlist(metrics, use.names = FALSE)),
    class = c("medsEvaluation", "data.frame"),
    source = files[[1]]
  )
}

# Python's json module writes NaN and Infinity, which are not JSON. Turn the
# bare tokens (never ones inside strings) into strings flattenMetrics knows.
readNonStandardJson <- function(file) {
  text <- paste(readLines(file, warn = FALSE), collapse = "\n")
  gsub("(?<=[:\\[,]|[:\\[,]\\s)\\s*(-?Infinity|NaN)(?=\\s*[,\\]}])", " \"\\1\"", text, perl = TRUE)
}

flattenMetrics <- function(x, prefix = NULL) {
  metrics <- list()
  for (name in names(x)) {
    key <- if (is.null(prefix)) name else paste(prefix, name, sep = "/")
    value <- x[[name]]
    if (is.list(value) && !is.null(names(value))) {
      metrics <- c(metrics, flattenMetrics(value, key))
    } else if (is.numeric(value) && length(value) == 1) {
      metrics[[key]] <- as.numeric(value)
    } else if (is.character(value) && length(value) == 1 && value %in% c("NaN", "Infinity", "-Infinity")) {
      metrics[[key]] <- c("NaN" = NA_real_, "Infinity" = Inf, "-Infinity" = -Inf)[[value]]
    }
  }
  metrics
}

#' @export
print.medsEvaluation <- function(x, ...) {
  cli::cli_text("{.cls medsEvaluation}: {nrow(x)} metric{?s}")
  print(as.data.frame(unclass(x)[c("metric", "value")]), row.names = FALSE)
  invisible(x)
}
