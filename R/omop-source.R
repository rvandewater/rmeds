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
#' as `vocabulary_id//concept_code`) and `vocabulary` / `cdm_source` (used by
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
#' is the layout `OMOP_MEDS` reads. File names are matched without regard to
#' case (`PERSON.csv` is the `person` table), and the `2b_` prefix of the
#' PhysioNet MIMIC-IV OMOP demo's vocabulary files is dropped.
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
  demoPrefixed <- startsWith(tables, "2b_") & !sub("^2b_", "", tables) %in% tables
  tables[demoPrefixed] <- sub("^2b_", "", tables[demoPrefixed])
  structure(
    list(path = path, tables = stats::setNames(as.list(entries), tables)),
    class = "omopSource"
  )
}

# OMOP_MEDS finds tables by exact lower-case name (`concept.csv`,
# `measurement/`). When a source's files are named otherwise (`CONCEPT.csv`,
# `2b_concept.csv`), this returns a folder of links with the expected names,
# or copies where links cannot be made. Otherwise it returns the source path.
omopToolInput <- function(omop, folder) {
  entries <- unlist(omop$tables, use.names = FALSE)
  extension <- ifelse(
    dir.exists(entries),
    "",
    tolower(regmatches(basename(entries), regexpr(omopFileExtension, basename(entries), ignore.case = TRUE)))
  )
  expected <- paste0(names(omop$tables), extension)
  if (all(basename(entries) == expected)) {
    return(omop$path)
  }
  unlink(folder, recursive = TRUE)
  dir.create(folder, recursive = TRUE)
  targets <- file.path(folder, expected)
  linked <- suppressWarnings(file.symlink(entries, targets))
  for (i in which(!linked)) {
    if (dir.exists(entries[i])) {
      file.copy(entries[i], folder, recursive = TRUE)
      file.rename(file.path(folder, basename(entries[i])), targets[i])
    } else {
      file.copy(entries[i], targets[i])
    }
  }
  normalizePath(folder, winslash = "/")
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
  if (isParquet) {
    return(arrow::open_dataset(entry, format = "parquet"))
  }
  openOmopCsv(entry)
}

# Arrow infers CSV column types from the first block of rows only, so an
# optional column that is empty there, a source value that starts out
# numeric, or a value that starts out whole fails further down. OMOP CSVs are
# therefore read with types from the CDM's naming conventions: text columns
# as text, value columns as doubles, and id and date columns as inferred
# unless the inference saw no values.
openOmopCsv <- function(entry) {
  inferred <- arrow::open_dataset(entry, format = "csv")$schema$fields
  fields <- lapply(inferred, function(field) arrow::field(field$name, omopColumnType(field$name, field$type)))
  arrow::open_dataset(entry, format = "csv", schema = do.call(arrow::schema, fields), skip = 1)
}

# CDM columns named *_id that hold text (CDM 5.3 and 5.4).
omopTextIds <- "(vocabulary|domain|concept_class|relationship|_source)_id$|^(unique_device|production)_id$"
omopNumberColumns <- c(
  "value_as_number", "range_low", "range_high", "quantity", "dose_value", "refills",
  "days_supply", "amount_value", "numerator_value", "denominator_value"
)

omopColumnType <- function(column, inferred = arrow::null()) {
  column <- tolower(column)
  unseen <- inferred$ToString() == "null"
  if (grepl("_(datetime|date)$", column)) {
    if (!unseen) inferred else if (grepl("_datetime$", column)) arrow::timestamp("us") else arrow::date32()
  } else if (grepl(omopTextIds, column)) {
    arrow::utf8()
  } else if (grepl("_id$|^(year|month|day)_of_birth$", column)) {
    if (unseen) arrow::int64() else inferred
  } else if (column %in% omopNumberColumns) {
    arrow::float64()
  } else {
    arrow::utf8()
  }
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
