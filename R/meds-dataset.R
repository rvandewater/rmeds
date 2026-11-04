# Stage: OMOP -> MEDS. Produces a medsDataset, the input of every MEDS-DEV step.

#' Convert OMOP CDM tables to MEDS with OMOP_MEDS
#'
#' Runs the `OMOP_MEDS` ETL in a separate process. `OMOP_MEDS` writes its
#' intermediate files to `outputFolder/pre_MEDS` and the MEDS dataset to
#' `outputFolder/MEDS_cohort`.
#'
#' @param omop An [omopSource()] or a path to a folder of CDM tables.
#' @param outputFolder Root output folder.
#' @param standardConceptsOnly Use standard concepts (`TRUE`, recommended for
#'   multi-site work) or source codes (`FALSE`, passes `prefer_source=true`).
#' @param joinOnVisit Passed to `OMOP_MEDS` as `join_on_visit`.
#' @param datasetName,omopVersion Recorded in the dataset metadata.
#' @param workers Number of parallel workers (`N_WORKERS`).
#' @param overwrite Delete `outputFolder` first.
#' @param extraOverrides Named list of further Hydra overrides for
#'   `OMOP_MEDS`, see [hydraOverrides()].
#'
#' @return A [medsDataset()].
#' @export
runOmopToMeds <- function(omop,
                          outputFolder,
                          standardConceptsOnly = TRUE,
                          joinOnVisit = FALSE,
                          datasetName = "OMOP",
                          omopVersion = "5.4",
                          workers = 1,
                          overwrite = FALSE,
                          extraOverrides = list()) {
  omop <- asOmopSource(omop)
  missing <- setdiff(c("person", "concept", "concept_relationship"), names(omop$tables))
  if (length(missing) > 0) {
    cli::cli_abort("OMOP_MEDS needs the {.val {missing}} table{?s}, which {.file {omop$path}} does not have.")
  }
  outputFolder <- prepareOutputFolder(outputFolder, overwrite)
  args <- c(
    hydraOverrides(
      raw_input_dir = omopToolInput(omop, file.path(outputFolder, ".rmeds", "omop_input")),
      root_output_dir = outputFolder,
      prefer_source = !standardConceptsOnly,
      join_on_visit = joinOnVisit,
      do_overwrite = FALSE
    ),
    do.call(hydraOverrides, extraOverrides)
  )
  runPythonTool(
    "omopToMeds",
    args = args,
    env = c(DATASET_NAME = datasetName, OMOP_VERSION = omopVersion, N_WORKERS = as.character(workers)),
    logFile = file.path(outputFolder, "rmeds-omop-to-meds.log")
  )
  medsDataset(file.path(outputFolder, "MEDS_cohort"))
}

#' A MEDS dataset on disk
#'
#' Wraps a MEDS root folder (`data/` and `metadata/`). The root of an
#' `OMOP_MEDS` output folder is accepted too; its `MEDS_cohort/` is used.
#'
#' @param path The MEDS root folder.
#'
#' @return A `medsDataset` object.
#' @export
medsDataset <- function(path) {
  path <- existingFolder(path, "MEDS")
  if (!dir.exists(file.path(path, "data")) && dir.exists(file.path(path, "MEDS_cohort", "data"))) {
    path <- file.path(path, "MEDS_cohort")
  }
  missing <- c("data", "metadata")[!dir.exists(file.path(path, c("data", "metadata")))]
  if (length(missing) > 0) {
    cli::cli_abort("{.file {path}} is not a MEDS dataset: no {.file {missing}} folder.")
  }
  structure(list(path = path), class = "medsDataset")
}

#' @rdname medsDataset
#' @param x A `medsDataset` or a path to one.
#' @export
asMedsDataset <- function(x) {
  if (inherits(x, "medsDataset")) x else medsDataset(x)
}

#' Read parts of a MEDS dataset
#'
#' `medsData()` opens the event data lazily as an Arrow dataset; the other
#' functions read the metadata files.
#'
#' @param meds A [medsDataset()] or a path to one.
#'
#' @return An [arrow::Dataset] (`medsData()`), a data frame (`medsCodes()`,
#'   `medsSubjectSplits()`) or a list (`medsMetadata()`).
#' @export
medsData <- function(meds) {
  arrow::open_dataset(file.path(asMedsDataset(meds)$path, "data"))
}

#' @rdname medsData
#' @export
medsCodes <- function(meds) {
  readMetadataParquet(meds, "codes.parquet")
}

#' @rdname medsData
#' @export
medsSubjectSplits <- function(meds) {
  readMetadataParquet(meds, "subject_splits.parquet")
}

#' @rdname medsData
#' @export
medsMetadata <- function(meds) {
  file <- file.path(asMedsDataset(meds)$path, "metadata", "dataset.json")
  if (file.exists(file)) jsonlite::read_json(file) else list()
}

readMetadataParquet <- function(meds, file) {
  path <- file.path(asMedsDataset(meds)$path, "metadata", file)
  if (!file.exists(path)) {
    cli::cli_abort("The MEDS dataset has no {.file metadata/{file}}.")
  }
  as.data.frame(arrow::read_parquet(path))
}

#' @export
print.medsDataset <- function(x, ...) {
  metadata <- medsMetadata(x)
  shards <- length(visibleFiles(file.path(x$path, "data"), "\\.parquet$"))
  cli::cli_text("{.cls medsDataset} {.val {metadata$dataset_name %||% basename(x$path)}} at {.file {x$path}}")
  cli::cli_text("{shards} data shard{?s}; ETL {metadata$etl_name %||% 'unknown'} {metadata$etl_version %||% ''}")
  invisible(x)
}

#' @export
summary.medsDataset <- function(object, ...) {
  splits <- tryCatch(medsSubjectSplits(object), error = function(e) NULL)
  codes <- tryCatch(medsCodes(object), error = function(e) NULL)
  events <- medsData(object) |> dplyr::count() |> dplyr::collect()
  structure(
    list(
      events = events$n,
      codes = if (is.null(codes)) NA_integer_ else nrow(codes),
      subjectsPerSplit = if (is.null(splits)) NULL else table(splits$split)
    ),
    class = "summary.medsDataset"
  )
}

#' @export
print.summary.medsDataset <- function(x, ...) {
  cli::cli_text("{x$events} event{?s}, {x$codes} distinct code{?s}")
  if (!is.null(x$subjectsPerSplit)) {
    cli::cli_text("Subjects per split: {paste(names(x$subjectsPerSplit), x$subjectsPerSplit, sep = ' = ', collapse = ', ')}")
  }
  invisible(x)
}
