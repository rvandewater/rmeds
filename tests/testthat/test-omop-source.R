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
