# Synthetic fixtures only: a tiny made-up CDM and a fake tool runner that
# writes what each Python tool would write.

syntheticCdm <- function() {
  connection <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbExecute(connection, "CREATE SCHEMA cdm")
  DBI::dbExecute(connection, "CREATE SCHEMA results")
  write <- function(schema, table, data) {
    DBI::dbWriteTable(connection, DBI::Id(schema = schema, table = table), data)
  }
  at <- function(x) as.POSIXct(x, tz = "UTC")
  write("cdm", "person", data.frame(
    PERSON_ID = 1:3,
    GENDER_CONCEPT_ID = c(8507L, 8532L, 8507L),
    YEAR_OF_BIRTH = c(1950L, 1960L, 1970L)
  ))
  write("cdm", "measurement", data.frame(
    measurement_id = 1:4,
    person_id = c(1L, 1L, 2L, 3L),
    measurement_concept_id = c(3016723L, 0L, 3016723L, 3019550L),
    measurement_datetime = at(c("2020-01-01 00:00:00", "2020-01-01 08:30:00", "2020-02-01 00:00:00", "2020-03-01 12:00:00")),
    value_as_number = c(1.1, NA, 0.9, 140),
    unit_concept_id = c(8840L, 0L, 0L, 8753L)
  ))
  write("cdm", "condition_occurrence", data.frame(
    condition_occurrence_id = 1:2,
    person_id = c(1L, 3L),
    condition_concept_id = c(201826L, 201826L),
    condition_start_datetime = at(c("2019-05-01 10:00:00", "2019-06-01 11:00:00"))
  ))
  write("cdm", "concept", data.frame(
    concept_id = 3016723L, vocabulary_id = "LOINC", concept_code = "2160-0", standard_concept = "S"
  ))
  write("cdm", "vocabulary", data.frame(
    vocabulary_id = c("None", "SNOMED"),
    vocabulary_version = c("v5.0 31-AUG-24", "2024-03-01")
  ))
  write("results", "cohort", data.frame(cohort_definition_id = c(1L, 1L, 2L), subject_id = c(1L, 2L, 3L)))
  connection
}

hydraValue <- function(args, key) {
  match <- grep(paste0("^\\+*", key, "="), args, value = TRUE)
  if (length(match) == 0) return(NULL)
  gsub("^'|'$", "", sub("^[^=]*=", "", match[[1]]))
}

writeParquet <- function(data, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(data, path)
}

fakeRunner <- function() {
  calls <- list()
  runner <- function(tool, args, env, logFile, verbose) {
    calls[[length(calls) + 1]] <<- list(tool = tool, args = args, env = env)
    switch(tool,
      omopToMeds = {
        root <- file.path(hydraValue(args, "root_output_dir"), "MEDS_cohort")
        writeParquet(data.frame(
          subject_id = c(1, 1, 2), time = as.POSIXct(c("2020-01-01", "2020-01-02", "2020-01-01"), tz = "UTC"),
          code = c("MEDS_BIRTH", "LOINC//x", "MEDS_BIRTH"), numeric_value = c(NA, 1, NA)
        ), file.path(root, "data", "train", "0.parquet"))
        writeParquet(data.frame(code = c("MEDS_BIRTH", "LOINC//x")), file.path(root, "metadata", "codes.parquet"))
        writeParquet(data.frame(subject_id = c(1, 2), split = c("train", "held_out")), file.path(root, "metadata", "subject_splits.parquet"))
        jsonlite::write_json(list(dataset_name = env[["DATASET_NAME"]], etl_name = "OMOP_MEDS"), file.path(root, "metadata", "dataset.json"), auto_unbox = TRUE)
      },
      medsDevTask = {
        out <- hydraValue(args, "output_dir")
        labels <- data.frame(subject_id = c(1, 2), prediction_time = as.POSIXct("2020-01-02", tz = "UTC"), boolean_value = c(TRUE, FALSE))
        writeParquet(labels[1, ], file.path(out, "train", "0.parquet"))
        writeParquet(labels[2, ], file.path(out, "held_out", "0.parquet"))
      },
      medsDevModel = {
        out <- hydraValue(args, "output_dir")
        predictions <- data.frame(subject_id = 2, prediction_time = as.POSIXct("2020-01-02", tz = "UTC"),
                                  boolean_value = FALSE, predicted_boolean_value = FALSE, predicted_boolean_probability = 0.2)
        writeParquet(predictions, file.path(out, "final", "held_out", "0.parquet"))
        writeParquet(predictions, file.path(out, "final", "tuning", "0.parquet"))
        writeParquet(predictions, file.path(out, ".venv", "ignored.parquet"))
      },
      medsDevEvaluation = {
        out <- hydraValue(args, "output_dir")
        jsonlite::write_json(list(
          samples_equally_weighted = list(roc_auc_score = 0.81, average_precision_score = 0.42, n_samples = 3, notes = "text"),
          subjects_equally_weighted = list(roc_auc_score = 0.79)
        ), file.path(out, "results.json"), auto_unbox = TRUE)
      }
    )
    invisible(list(tool = tool, args = args, status = 0, logFile = logFile))
  }
  list(runner = runner, calls = function() calls)
}
