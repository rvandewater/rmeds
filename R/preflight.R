# Stage: mapping pre-flight. Reports how a site's OMOP mapping will shape its
# MEDS codes, as aggregate shares only, so the report can be shared. It
# measures; it does not change the data.

# Per domain table: the standard concept column, the event datetime column,
# and (for measurement) the unit and value columns.
preflightColumns <- list(
  condition_occurrence = list(concept = "condition_concept_id", datetime = "condition_start_datetime"),
  drug_exposure = list(concept = "drug_concept_id", datetime = "drug_exposure_start_datetime"),
  procedure_occurrence = list(concept = "procedure_concept_id", datetime = "procedure_datetime"),
  measurement = list(
    concept = "measurement_concept_id", datetime = "measurement_datetime",
    unit = "unit_concept_id", value = "value_as_number"
  ),
  observation = list(concept = "observation_concept_id", datetime = "observation_datetime"),
  device_exposure = list(concept = "device_concept_id", datetime = "device_exposure_start_datetime"),
  visit_occurrence = list(concept = "visit_concept_id", datetime = "visit_start_datetime"),
  specimen = list(concept = "specimen_concept_id", datetime = "specimen_datetime")
)

#' Report mapping quality before running the ETL
#'
#' For each domain table: rows, the share of rows with no standard concept
#' (`concept_id` 0 or missing), the share of the remaining rows whose concept
#' id is not in the exported `concept` table (`OMOP_MEDS` cannot turn those
#' into `vocabulary_id//concept_code` codes and falls back to source or
#' placeholder codes), the share of event times at exactly midnight
#' (usually date-only source data, a leakage risk for prediction times), and
#' for measurements the share of numeric values without a unit. Also reports
#' the vocabulary and CDM versions when those tables were exported.
#'
#' @param omop An [omopSource()] or a path to one.
#'
#' @return A `mappingPreflight` object: a list with `tables` (a data frame
#'   with columns `table`, `rows`, `unmappedShare`, `notInVocabularyShare`,
#'   `midnightShare` and `missingUnitShare`),
#'   `vocabularyVersion` and `cdmVersion`.
#' @export
runMappingPreflight <- function(omop) {
  omop <- asOmopSource(omop)
  present <- intersect(names(preflightColumns), names(omop$tables))
  concepts <- openOmopTable(omop, "concept")
  rows <- lapply(present, function(table) {
    preflightTable(openOmopTable(omop, table), table, preflightColumns[[table]], concepts)
  })
  structure(
    list(
      tables = do.call(rbind, rows) %||% emptyPreflightTable(),
      vocabularyVersion = lookupValue(omop, "vocabulary", "vocabulary_id", "None", "vocabulary_version"),
      cdmVersion = lookupValue(omop, "cdm_source", NULL, NULL, "cdm_version")
    ),
    class = "mappingPreflight"
  )
}

preflightTable <- function(data, table, columns, concepts = NULL) {
  fields <- names(data)
  total <- countRows(data)
  share <- function(numerator, denominator) if (is.na(denominator) || denominator == 0) NA_real_ else numerator / denominator

  unmapped <- NA_real_
  notInVocabulary <- NA_real_
  if (columns$concept %in% fields) {
    concept <- rlang::sym(columns$concept)
    unmapped <- share(countRows(dplyr::filter(data, is.na(!!concept) | !!concept == 0)), total)
    if (!is.null(concepts) && "concept_id" %in% names(concepts)) {
      notInVocabulary <- tryCatch({
        mapped <- data |>
          dplyr::filter(!is.na(!!concept) & !!concept != 0) |>
          dplyr::transmute(concept_id = as.numeric(!!concept))
        known <- dplyr::transmute(concepts, concept_id = as.numeric(.data$concept_id))
        mappedRows <- countRows(mapped)
        share(mappedRows - countRows(dplyr::semi_join(mapped, known, by = "concept_id")), mappedRows)
      }, error = function(e) NA_real_)
    }
  }

  midnight <- NA_real_
  if (columns$datetime %in% fields) {
    time <- rlang::sym(columns$datetime)
    midnight <- tryCatch({
      timed <- dplyr::filter(data, !is.na(!!time))
      atMidnight <- dplyr::filter(timed, hour(!!time) == 0 & minute(!!time) == 0 & second(!!time) == 0)
      share(countRows(atMidnight), countRows(timed))
    }, error = function(e) NA_real_)
  }

  missingUnit <- NA_real_
  if (!is.null(columns$unit) && all(c(columns$unit, columns$value) %in% fields)) {
    unit <- rlang::sym(columns$unit)
    valued <- dplyr::filter(data, !is.na(!!rlang::sym(columns$value)))
    missingUnit <- share(countRows(dplyr::filter(valued, is.na(!!unit) | !!unit == 0)), countRows(valued))
  }

  data.frame(
    table = table,
    rows = total,
    unmappedShare = unmapped,
    notInVocabularyShare = notInVocabulary,
    midnightShare = midnight,
    missingUnitShare = missingUnit
  )
}

emptyPreflightTable <- function() {
  data.frame(
    table = character(), rows = numeric(), unmappedShare = numeric(),
    notInVocabularyShare = numeric(), midnightShare = numeric(), missingUnitShare = numeric()
  )
}

countRows <- function(data) {
  as.numeric(dplyr::collect(dplyr::count(data))$n)
}

lookupValue <- function(omop, table, keyColumn, key, valueColumn) {
  data <- openOmopTable(omop, table)
  if (is.null(data) || !valueColumn %in% names(data)) {
    return(NA_character_)
  }
  if (!is.null(keyColumn)) {
    data <- dplyr::filter(data, !!rlang::sym(keyColumn) == key)
  }
  values <- dplyr::collect(utils::head(dplyr::select(data, dplyr::all_of(valueColumn)), 1))[[1]]
  if (length(values) == 0) NA_character_ else as.character(values)
}

#' @export
print.mappingPreflight <- function(x, ...) {
  cli::cli_text("{.cls mappingPreflight}: vocabulary {.val {x$vocabularyVersion}}, CDM {.val {x$cdmVersion}}")
  shown <- x$tables
  for (column in c("unmappedShare", "notInVocabularyShare", "midnightShare", "missingUnitShare")) {
    shown[[column]] <- ifelse(is.na(shown[[column]]), "-", sprintf("%.1f%%", 100 * shown[[column]]))
  }
  print(shown, row.names = FALSE)
  invisible(x)
}
