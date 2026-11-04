# Stage: task labelling with MEDS-DEV (ACES). Produces medsLabels.

#' Extract task labels with MEDS-DEV
#'
#' Runs `meds-dev-task`, which applies the task's ACES criteria to the MEDS
#' dataset. MEDS-DEV has no OMOP dataset entry yet, so OMOP sites normally
#' pass their own `predicatesPath` (an ACES predicates file written in the
#' dataset's codes); `dataset` then only names the data in the output.
#'
#' @param meds A [medsDataset()] or a path to one.
#' @param task MEDS-DEV task name, e.g. `"mortality/in_icu/first_24h"`
#'   (see [listMedsDevTasks()]).
#' @param outputFolder Folder for the label shards.
#' @param dataset MEDS-DEV dataset name whose predicates to use, or a label
#'   for the data when `predicatesPath` is given.
#' @param predicatesPath Optional path to an ACES predicates YAML file.
#' @param overwrite Delete `outputFolder` first.
#'
#' @return A [medsLabels()] object.
#' @export
extractTaskLabels <- function(meds,
                              task,
                              outputFolder,
                              dataset = "OMOP",
                              predicatesPath = NULL,
                              overwrite = FALSE) {
  meds <- asMedsDataset(meds)
  outputFolder <- prepareOutputFolder(outputFolder, overwrite)
  if (!is.null(predicatesPath)) {
    predicatesPath <- normalizePath(predicatesPath, winslash = "/", mustWork = TRUE)
  }
  checkShellSafePaths(meds$path, outputFolder, predicatesPath)
  runPythonTool(
    "medsDevTask",
    args = hydraOverrides(
      task = task,
      dataset = dataset,
      dataset_dir = meds$path,
      output_dir = outputFolder,
      "++dataset_predicates_path" = predicatesPath
    ),
    logFile = file.path(outputFolder, ".rmeds", "meds-dev-task.log")
  )
  medsLabels(outputFolder, task = task, predicatesPath = predicatesPath)
}

#' Task labels on disk
#'
#' Wraps a folder of MEDS label Parquet files (`subject_id`,
#' `prediction_time` and one value column such as `boolean_value`).
#'
#' @param path The labels folder.
#' @param task The task name, if known.
#' @param predicatesPath The predicates file the labels were extracted with,
#'   if known. [runMedsDevModel()] passes it on to models that need it.
#'
#' @return A `medsLabels` object.
#' @export
medsLabels <- function(path, task = NULL, predicatesPath = NULL) {
  path <- existingFolder(path, "Labels")
  if (length(visibleFiles(path, "\\.parquet$")) == 0) {
    cli::cli_abort("No label Parquet files in {.file {path}}.")
  }
  structure(
    list(path = path, task = task %||% basename(path), predicatesPath = predicatesPath),
    class = "medsLabels"
  )
}

#' @rdname medsLabels
#' @param x A `medsLabels` object or a path to one.
#' @export
asMedsLabels <- function(x) {
  if (inherits(x, "medsLabels")) x else medsLabels(x)
}

#' Open task labels as an Arrow dataset
#'
#' @param labels A [medsLabels()] object or a path to one.
#'
#' @return An [arrow::Dataset].
#' @export
labelData <- function(labels) {
  labels <- asMedsLabels(labels)
  arrow::open_dataset(visibleFiles(labels$path, "\\.parquet$"))
}

#' @export
print.medsLabels <- function(x, ...) {
  cli::cli_text("{.cls medsLabels} for task {.val {x$task}} at {.file {x$path}}")
  invisible(x)
}

#' @export
summary.medsLabels <- function(object, ...) {
  data <- labelData(object)
  counts <- if ("boolean_value" %in% names(data)) {
    data |>
      dplyr::summarise(labels = dplyr::n(), positives = sum(as.integer(.data$boolean_value), na.rm = TRUE)) |>
      dplyr::collect()
  } else {
    data |> dplyr::summarise(labels = dplyr::n()) |> dplyr::collect()
  }
  structure(c(list(task = object$task), as.list(counts)), class = "summary.medsLabels")
}

#' @export
print.summary.medsLabels <- function(x, ...) {
  cli::cli_text("Task {.val {x$task}}: {x$labels} label{?s}")
  if (!is.null(x$positives)) {
    cli::cli_text("Positive: {x$positives} ({round(100 * x$positives / x$labels, 1)}%)")
  }
  invisible(x)
}
