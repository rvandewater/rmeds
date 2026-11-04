# Stage: model training and prediction with MEDS-DEV. Produces medsModelRun.

predictionColumns <- c("predicted_boolean_probability", "predicted_boolean_value")

#' Train a MEDS-DEV model and predict
#'
#' Runs `meds-dev-model`. MEDS-DEV installs the model's own requirements into
#' a separate environment, so any model in [listMedsDevModels()] can run from
#' the same rmeds environment. With `mode = "full"` MEDS-DEV runs every stage
#' the model supports (pre-training, fine-tuning, held-out prediction) and
#' resumes at the first unfinished stage on re-runs.
#'
#' @param meds A [medsDataset()] or a path to one.
#' @param labels A [medsLabels()] object or path (not needed for
#'   unsupervised pre-training).
#' @param model MEDS-DEV model name, e.g. `"random_predictor"` or `"meds_tab/tiny"`.
#' @param outputFolder Folder for model artefacts and predictions.
#' @param mode `"full"`, `"train"` or `"predict"`.
#' @param datasetType `"full"`, `"supervised"` or `"unsupervised"`.
#' @param datasetName,taskName Required by MEDS-DEV in full mode; default to
#'   the dataset metadata and the labels' task.
#' @param split Data split to predict on, e.g. `"held_out"`.
#' @param modelInitializationFolder Output of an earlier training run to
#'   start from.
#' @param predicatesPath ACES predicates file, for models whose commands use
#'   it (e.g. `random_predictor`). Defaults to the file the labels were
#'   extracted with.
#' @param demo Use the model's small demo configuration.
#' @param overwrite Ask MEDS-DEV to clear `outputFolder` first.
#'
#' @return A [medsModelRun()] object.
#' @export
runMedsDevModel <- function(meds,
                            labels = NULL,
                            model,
                            outputFolder,
                            mode = c("full", "train", "predict"),
                            datasetType = c("full", "supervised", "unsupervised"),
                            datasetName = NULL,
                            taskName = NULL,
                            split = NULL,
                            modelInitializationFolder = NULL,
                            predicatesPath = NULL,
                            demo = FALSE,
                            overwrite = FALSE) {
  mode <- rlang::arg_match(mode)
  datasetType <- rlang::arg_match(datasetType)
  meds <- asMedsDataset(meds)
  labels <- if (is.null(labels)) NULL else asMedsLabels(labels)
  if (is.null(labels) && datasetType != "unsupervised") {
    cli::cli_abort("{.arg labels} is required unless {.code datasetType = \"unsupervised\"}.")
  }
  if (mode == "full") {
    datasetName <- datasetName %||% medsMetadata(meds)$dataset_name %||% "OMOP"
    taskName <- taskName %||% labels$task
  }
  predicatesPath <- predicatesPath %||% labels$predicatesPath
  outputFolder <- prepareOutputFolder(outputFolder)
  checkShellSafePaths(meds$path, labels$path, outputFolder)
  runPythonTool(
    "medsDevModel",
    args = hydraOverrides(
      model = model,
      mode = mode,
      dataset_type = datasetType,
      dataset_dir = meds$path,
      labels_dir = labels$path,
      output_dir = outputFolder,
      dataset_name = datasetName,
      task_name = taskName,
      split = split,
      model_initialization_dir = modelInitializationFolder,
      predicates_path = predicatesPath,
      demo = demo,
      do_overwrite = overwrite
    ),
    logFile = file.path(outputFolder, ".rmeds", "meds-dev-model.log")
  )
  medsModelRun(outputFolder, model = model, mode = mode)
}

#' A MEDS-DEV model run on disk
#'
#' @param path The model output folder.
#' @param model,mode The model name and run mode, if known.
#'
#' @return A `medsModelRun` object.
#' @export
medsModelRun <- function(path, model = NA_character_, mode = NA_character_) {
  path <- existingFolder(path, "Model output")
  structure(list(path = path, model = model, mode = mode), class = "medsModelRun")
}

#' @export
print.medsModelRun <- function(x, ...) {
  cli::cli_text("{.cls medsModelRun} {.val {x$model}} ({x$mode}) at {.file {x$path}}")
  invisible(x)
}

#' Find prediction files in a model run
#'
#' Looks for Parquet files with MEDS-Evaluation prediction columns
#' (`predicted_boolean_probability` or `predicted_boolean_value`). When a run
#' holds predictions for several splits, only `held_out` ones are returned.
#' Only file schemas are read, not the data.
#'
#' @param run A [medsModelRun()] or a path to one.
#'
#' @return A character vector of Parquet file paths.
#' @export
findPredictions <- function(run) {
  path <- if (inherits(run, "medsModelRun")) run$path else existingFolder(run, "Model output")
  files <- visibleFiles(path, "\\.parquet$")
  isPrediction <- vapply(
    files,
    function(file) any(predictionColumns %in% names(arrow::open_dataset(file)$schema)),
    logical(1)
  )
  files <- files[isPrediction]
  heldOut <- files[grepl("held_out", files, fixed = TRUE)]
  if (length(heldOut) > 0) heldOut else files
}
