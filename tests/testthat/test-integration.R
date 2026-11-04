# End to end against the real Python tools on synthetic data. Opt in with
# RMEDS_INTEGRATION=true; the first run downloads the pinned packages.

test_that("the full pipeline runs against OMOP_MEDS and MEDS-DEV", {
  skip_if_not(identical(Sys.getenv("RMEDS_INTEGRATION"), "true"), "Set RMEDS_INTEGRATION=true to run.")
  skip_if_not_installed("duckdb")
  withr::local_options(rmeds.verbose = FALSE, rmeds.runner = NULL)
  setupPythonEnvironment()
  connection <- syntheticCdmDuckdb(nPersons = 400)
  on.exit(DBI::dbDisconnect(connection, shutdown = TRUE))
  root <- withr::local_tempdir()
  # MEDS-DEV builds shell commands from paths, so keep every input in the
  # (space-free) temp folder rather than the package source tree.
  predicates <- file.path(root, "predicates.yaml")
  file.copy(test_path("fixtures", "synthetic_predicates.yaml"), predicates)

  omop <- suppressWarnings(exportCdmToParquet(connection = connection, cdmDatabaseSchema = "cdm", outputFolder = file.path(root, "omop")))
  preflight <- runMappingPreflight(omop)
  meds <- runOmopToMeds(omop, file.path(root, "meds"), datasetName = "SYNTHETIC")
  labels <- extractTaskLabels(
    meds, "mortality/in_icu/first_24h", file.path(root, "labels"),
    predicatesPath = predicates
  )
  run <- runMedsDevModel(meds, labels, model = "random_predictor", outputFolder = file.path(root, "model"))
  evaluation <- evaluatePredictions(run)
  files <- exportResults(evaluation, preflight, file.path(root, "share"), databaseId = "synthetic")

  expect_true("LOINC//2160-0" %in% medsCodes(meds)$code)
  expect_gt(summary(labels)$labels, 0)
  expect_length(findPredictions(run), 1)
  expect_true("samples_equally_weighted/roc_auc_score" %in% evaluation$metric)
  expect_true(all(file.exists(files)))
})
