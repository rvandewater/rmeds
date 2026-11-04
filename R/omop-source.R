# OMOP CDM tables as files on disk: the hand-off between a database and the
# OMOP_MEDS ETL. Anything that can produce such a folder (this export, an
# existing CSV dump, another tool) works with the rest of the pipeline.

omopFileExtension <- "\\.(csv\\.gz|csv|parquet)$"

# Tables that carry no person_id and are therefore never cohort-filtered.
omopReferenceTables <- c(
  "concept", "concept_relationship", "vocabulary", "care_site", "location", "provider", "cdm_source"
)

#' Default CDM tables to export
#'
#' The clinical tables `OMOP_MEDS` turns into events, plus `concept` and
#' `concept_relationship` (both required by `OMOP_MEDS`, which builds codes
#' from concept names) and `vocabulary` / `cdm_source` (used by
#' [runMappingPreflight()]).
#'
#' @return A character vector of table names.
#' @export
defaultCdmTables <- function() {
  c(
    "person", "observation_period", "death", "visit_occurrence", "visit_detail",
    "condition_occurrence", "drug_exposure", "procedure_occurrence",
    "device_exposure", "measurement", "observation", "specimen", "note",
    "condition_era", "drug_era", "dose_era", "care_site",
    "concept", "concept_relationship", "vocabulary", "cdm_source"
  )
}

#' A folder of OMOP CDM tables
#'
#' Wraps a folder with one entry per CDM table: `person.csv`,
#' `person.csv.gz`, `person.parquet`, or a `person/` folder of shards. This
#' is the layout `OMOP_MEDS` reads.
#'
#' @param path The folder.
#'
#' @return An `omopSource` object.
#' @export
omopSource <- function(path) {
  path <- existingFolder(path, "OMOP")
  entries <- list.files(path, full.names = TRUE)
  entries <- entries[!startsWith(basename(entries), ".")]
  keep <- dir.exists(entries) | grepl(omopFileExtension, entries, ignore.case = TRUE)
  entries <- entries[keep]
  tables <- tolower(sub(omopFileExtension, "", basename(entries), ignore.case = TRUE))
  structure(
    list(path = path, tables = stats::setNames(as.list(entries), tables)),
    class = "omopSource"
  )
}

#' @rdname omopSource
#' @param x An `omopSource` or a path to one.
#' @export
asOmopSource <- function(x) {
  if (inherits(x, "omopSource")) x else omopSource(x)
}

#' @export
print.omopSource <- function(x, ...) {
  cli::cli_text("{.cls omopSource} at {.file {x$path}}")
  cli::cli_text("{length(x$tables)} table{?s}: {.val {sort(names(x$tables))}}")
  invisible(x)
}

#' Open one CDM table of an `omopSource` as an Arrow dataset
#'
#' @param omop An `omopSource` or a path to one.
#' @param table Table name, e.g. `"measurement"`.
#'
#' @return An [arrow::Dataset], or `NULL` if the table is absent.
#' @export
openOmopTable <- function(omop, table) {
  omop <- asOmopSource(omop)
  entry <- omop$tables[[tolower(table)]]
  if (is.null(entry)) {
    return(NULL)
  }
  isParquet <- if (dir.exists(entry)) {
    length(list.files(entry, pattern = "\\.parquet$", recursive = TRUE, ignore.case = TRUE)) > 0
  } else {
    grepl("\\.parquet$", entry, ignore.case = TRUE)
  }
  arrow::open_dataset(entry, format = if (isParquet) "parquet" else "csv")
}

#' Export CDM tables from a database to Parquet
#'
#' Streams each table in batches to `outputFolder/<table>/part-00000.parquet`,
#' `part-00001.parquet`, ..., so tables larger than memory can be exported.
#' Column names are lower-cased. Tables missing from the database are skipped
#' with a warning.
#'
#' Works with any DBI connection. Pass `connectionDetails` from
#' `DatabaseConnector::createConnectionDetails()` to let rmeds open and close
#' the connection itself.
#'
#' @param connectionDetails A `DatabaseConnector` connectionDetails object.
#' @param connection An open DBI connection (alternative to
#'   `connectionDetails`).
#' @param cdmDatabaseSchema Schema holding the CDM tables.
#' @param outputFolder Folder to write the tables to.
#' @param tables Tables to export.
#' @param cohortDatabaseSchema,cohortTable,cohortIds Optional: keep only
#'   people in these cohorts (applied to tables with a `person_id`).
#' @param batchSize Rows fetched and written per Parquet file.
#' @param overwrite Delete `outputFolder` first.
#'
#' @return An [omopSource()] for `outputFolder`.
#' @export
exportCdmToParquet <- function(connectionDetails = NULL,
                               connection = NULL,
                               cdmDatabaseSchema,
                               outputFolder,
                               tables = defaultCdmTables(),
                               cohortDatabaseSchema = NULL,
                               cohortTable = NULL,
                               cohortIds = NULL,
                               batchSize = 1e6,
                               overwrite = FALSE) {
  if (is.null(connection) == is.null(connectionDetails)) {
    cli::cli_abort("Provide exactly one of {.arg connectionDetails} or {.arg connection}.")
  }
  if (is.null(connection)) {
    rlang::check_installed("DatabaseConnector", "to connect with connectionDetails")
    connection <- DatabaseConnector::connect(connectionDetails)
    on.exit(DatabaseConnector::disconnect(connection), add = TRUE)
  }
  outputFolder <- prepareOutputFolder(outputFolder, overwrite)
  personFilter <- cohortPersonFilter(cohortDatabaseSchema, cohortTable, cohortIds)

  for (table in tolower(tables)) {
    filter <- if (table %in% omopReferenceTables) "" else personFilter
    sql <- sprintf("SELECT * FROM %s.%s%s", cdmDatabaseSchema, table, filter)
    rows <- tryCatch(
      exportQuery(connection, sql, file.path(outputFolder, table), batchSize),
      error = function(e) {
        unlink(file.path(outputFolder, table), recursive = TRUE)
        cli::cli_warn("Skipped {.val {table}}: {conditionMessage(e)}")
        NA
      }
    )
    if (!is.na(rows)) cli::cli_inform("Exported {.val {table}}.")
  }
  omopSource(outputFolder)
}

cohortPersonFilter <- function(cohortDatabaseSchema, cohortTable, cohortIds) {
  if (is.null(cohortTable)) {
    return("")
  }
  if (is.null(cohortDatabaseSchema) || is.null(cohortIds)) {
    cli::cli_abort("{.arg cohortTable} needs {.arg cohortDatabaseSchema} and {.arg cohortIds}.")
  }
  sprintf(
    " WHERE person_id IN (SELECT subject_id FROM %s.%s WHERE cohort_definition_id IN (%s))",
    cohortDatabaseSchema, cohortTable, paste(as.integer(cohortIds), collapse = ", ")
  )
}

# Streams one query to numbered Parquet files; always writes at least one
# file so empty tables keep their schema. Returns the number of rows.
exportQuery <- function(connection, sql, tableFolder, batchSize) {
  result <- DBI::dbSendQuery(connection, sql)
  on.exit(DBI::dbClearResult(result), add = TRUE)
  dir.create(tableFolder, recursive = TRUE, showWarnings = FALSE)
  part <- 0
  rows <- 0
  repeat {
    chunk <- DBI::dbFetch(result, n = batchSize)
    if (nrow(chunk) == 0 && part > 0) break
    names(chunk) <- tolower(names(chunk))
    arrow::write_parquet(chunk, file.path(tableFolder, sprintf("part-%05d.parquet", part)))
    rows <- rows + nrow(chunk)
    part <- part + 1
    if (DBI::dbHasCompleted(result)) break
  }
  rows
}
