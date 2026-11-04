test_that("exportCdmToParquet streams tables to Parquet folders", {
  skip_if_not_installed("duckdb")
  connection <- syntheticCdm()
  on.exit(DBI::dbDisconnect(connection, shutdown = TRUE))
  outputFolder <- withr::local_tempdir()

  expect_warning(
    omop <- exportCdmToParquet(
      connection = connection, cdmDatabaseSchema = "cdm", outputFolder = outputFolder,
      tables = c("person", "measurement", "vocabulary", "drug_exposure"), batchSize = 2
    ),
    "drug_exposure"
  )

  expect_s3_class(omop, "omopSource")
  expect_setequal(names(omop$tables), c("person", "measurement", "vocabulary"))
  expect_length(list.files(file.path(outputFolder, "measurement")), 2)
  person <- dplyr::collect(openOmopTable(omop, "person"))
  expect_true("person_id" %in% names(person))
  expect_equal(nrow(person), 3)
})

test_that("cohort filtering keeps only cohort members in person tables", {
  skip_if_not_installed("duckdb")
  connection <- syntheticCdm()
  on.exit(DBI::dbDisconnect(connection, shutdown = TRUE))

  omop <- exportCdmToParquet(
    connection = connection, cdmDatabaseSchema = "cdm", outputFolder = withr::local_tempdir(),
    tables = c("person", "measurement", "vocabulary"),
    cohortDatabaseSchema = "results", cohortTable = "cohort", cohortIds = 1
  )

  expect_setequal(dplyr::collect(openOmopTable(omop, "person"))$person_id, c(1, 2))
  expect_equal(nrow(dplyr::collect(openOmopTable(omop, "vocabulary"))), 2)
})

test_that("exportCdmToParquet needs exactly one connection argument", {
  expect_error(exportCdmToParquet(cdmDatabaseSchema = "cdm", outputFolder = tempdir()), "exactly one")
})

test_that("omopSource recognises CSV files and shard folders", {
  folder <- withr::local_tempdir()
  utils::write.csv(data.frame(person_id = 1), file.path(folder, "PERSON.csv"), row.names = FALSE)
  dir.create(file.path(folder, "measurement"))
  writeLines("ignore", file.path(folder, "README.txt"))

  omop <- omopSource(folder)

  expect_setequal(names(omop$tables), c("person", "measurement"))
  expect_equal(nrow(dplyr::collect(openOmopTable(omop, "person"))), 1)
  expect_null(openOmopTable(omop, "death"))
})

test_that("omopSource drops the MIMIC demo's 2b_ prefix unless it would clash", {
  folder <- withr::local_tempdir()
  for (file in c("2b_concept.csv", "2b_vocabulary.csv", "vocabulary.csv")) {
    utils::write.csv(data.frame(id = 1), file.path(folder, file), row.names = FALSE)
  }

  omop <- omopSource(folder)

  expect_setequal(names(omop$tables), c("concept", "2b_vocabulary", "vocabulary"))
})

test_that("openOmopTable types CSV columns by CDM convention, not the first block", {
  folder <- withr::local_tempdir()
  n <- 2e5 # more than one 1 MB block of CSV, so Arrow infers types from the first rows only
  rows <- data.frame(
    measurement_id = seq_len(n),
    measurement_type_concept_id = c(rep(NA, n - 1), 45878594),
    measurement_source_value = c(rep("50912", n - 1), "HR [bpm]"),
    value_as_number = c(rep(1, n - 1), 1.5)
  )
  file <- file.path(folder, "measurement.csv")
  utils::write.csv(rows, file, row.names = FALSE, na = "")
  expect_error(dplyr::collect(arrow::open_dataset(file, format = "csv")), "conversion error")
  utils::write.csv(
    data.frame(concept_id = 1, vocabulary_id = "LOINC", concept_code = "2160-0", valid_start_date = "1970-01-01"),
    file.path(folder, "concept.csv"), row.names = FALSE
  )

  omop <- omopSource(folder)
  measurement <- dplyr::collect(openOmopTable(omop, "measurement"))
  concept <- dplyr::collect(openOmopTable(omop, "concept"))

  expect_equal(nrow(measurement), n)
  expect_equal(sum(measurement$measurement_type_concept_id, na.rm = TRUE), 45878594)
  expect_equal(measurement$measurement_source_value[n], "HR [bpm]")
  expect_equal(measurement$value_as_number[n], 1.5)
  expect_type(concept$vocabulary_id, "character")
  expect_equal(omopColumnType("specimen_source_id")$ToString(), "string")
  expect_equal(omopColumnType("reverse_relationship_id")$ToString(), "string")
  expect_equal(omopColumnType("unique_device_id")$ToString(), "string")
  expect_equal(omopColumnType("specimen_concept_id")$ToString(), "int64")
  expect_equal(omopColumnType("care_site_id", arrow::utf8())$ToString(), "string")
  expect_s3_class(concept$valid_start_date, "Date")
})
