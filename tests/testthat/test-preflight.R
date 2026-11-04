test_that("runMappingPreflight reports aggregate mapping shares", {
  skip_if_not_installed("duckdb")
  connection <- syntheticCdm()
  on.exit(DBI::dbDisconnect(connection, shutdown = TRUE))
  omop <- exportCdmToParquet(
    connection = connection, cdmDatabaseSchema = "cdm", outputFolder = withr::local_tempdir(),
    tables = c("measurement", "condition_occurrence", "concept", "vocabulary")
  )

  preflight <- runMappingPreflight(omop)

  expect_s3_class(preflight, "mappingPreflight")
  expect_equal(preflight$vocabularyVersion, "v5.0 31-AUG-24")
  expect_true(is.na(preflight$cdmVersion))
  measurement <- preflight$tables[preflight$tables$table == "measurement", ]
  expect_equal(measurement$rows, 4)
  expect_equal(measurement$unmappedShare, 1 / 4)
  expect_equal(measurement$notInVocabularyShare, 1 / 3)
  expect_equal(measurement$midnightShare, 2 / 4)
  expect_equal(measurement$missingUnitShare, 1 / 3)
  condition <- preflight$tables[preflight$tables$table == "condition_occurrence", ]
  expect_equal(condition$unmappedShare, 0)
  expect_equal(condition$notInVocabularyShare, 1)
  expect_true(is.na(condition$missingUnitShare))
  expect_output(print(preflight), "25.0%")
})

test_that("runMappingPreflight handles a source without domain tables", {
  folder <- withr::local_tempdir()
  utils::write.csv(data.frame(person_id = 1), file.path(folder, "person.csv"), row.names = FALSE)

  preflight <- runMappingPreflight(folder)

  expect_equal(nrow(preflight$tables), 0)
  expect_true(is.na(preflight$vocabularyVersion))
})
