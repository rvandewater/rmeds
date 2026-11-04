test_that("the pipeline chains steps through objects with a fake runner", {
  fake <- fakeRunner()
  withr::local_options(rmeds.runner = fake$runner)
  root <- withr::local_tempdir()
  omopFolder <- file.path(root, "omop")
  dir.create(omopFolder)
  utils::write.csv(data.frame(person_id = 1), file.path(omopFolder, "person.csv"), row.names = FALSE)
  predicates <- file.path(root, "predicates.yaml")
  writeLines("predicates: {}", predicates)

  meds <- runOmopToMeds(omopFolder, file.path(root, "meds"), datasetName = "SITE_A")
  labels <- extractTaskLabels(meds, "mortality/in_icu/first_24h", file.path(root, "labels"), predicatesPath = predicates)
  run <- runMedsDevModel(meds, labels, model = "meds_tab", outputFolder = file.path(root, "model"))
  evaluation <- evaluatePredictions(run)

  calls <- fake$calls()
  expect_equal(vapply(calls, `[[`, "", "tool"), c("omopToMeds", "medsDevTask", "medsDevModel", "medsDevEvaluation"))

  etlArgs <- calls[[1]]$args
  expect_equal(hydraValue(etlArgs, "prefer_source"), "false")
  expect_equal(hydraValue(etlArgs, "raw_input_dir"), normalizePath(omopFolder, winslash = "/"))
  expect_equal(calls[[1]]$env[["DATASET_NAME"]], "SITE_A")

  expect_s3_class(meds, "medsDataset")
  expect_equal(basename(meds$path), "MEDS_cohort")
  expect_equal(medsMetadata(meds)$dataset_name, "SITE_A")
  expect_equal(summary(meds)$events, 3)

  expect_equal(hydraValue(calls[[2]]$args, "dataset_predicates_path"), normalizePath(predicates, winslash = "/"))
  expect_true(any(startsWith(calls[[2]]$args, "++dataset_predicates_path=")))
  expect_equal(summary(labels)$positives, 1)

  modelArgs <- calls[[3]]$args
  expect_equal(hydraValue(modelArgs, "dataset_name"), "SITE_A")
  expect_equal(hydraValue(modelArgs, "task_name"), "mortality/in_icu/first_24h")
  expect_equal(hydraValue(modelArgs, "labels_dir"), labels$path)
  expect_equal(hydraValue(modelArgs, "predicates_path"), normalizePath(predicates, winslash = "/"))

  predictions <- findPredictions(run)
  expect_length(predictions, 1)
  expect_match(predictions, "held_out")
  expect_equal(hydraValue(calls[[4]]$args, "predictions_path"), predictions)

  expect_s3_class(evaluation, "medsEvaluation")
  expect_equal(evaluation$value[evaluation$metric == "samples_equally_weighted/roc_auc_score"], 0.81)
  expect_false(any(grepl("notes", evaluation$metric)))
})

test_that("steps accept paths instead of objects", {
  fake <- fakeRunner()
  withr::local_options(rmeds.runner = fake$runner)
  root <- withr::local_tempdir()
  fake$runner("omopToMeds", hydraOverrides(root_output_dir = root), c(DATASET_NAME = "X"), NULL, FALSE)

  labels <- extractTaskLabels(root, "some/task", file.path(root, "labels"), dataset = "MIMIC-IV")

  expect_equal(medsDataset(root)$path, normalizePath(file.path(root, "MEDS_cohort"), winslash = "/"))
  expect_equal(hydraValue(fake$calls()[[2]]$args, "dataset"), "MIMIC-IV")
  expect_null(hydraValue(fake$calls()[[2]]$args, "dataset_predicates_path"))
  expect_s3_class(asMedsLabels(labels$path), "medsLabels")
})

test_that("supervised model runs require labels", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "data"))
  dir.create(file.path(root, "metadata"))
  expect_error(runMedsDevModel(root, model = "meds_tab", outputFolder = file.path(root, "m")), "labels")
})

test_that("exportResults suppresses small counts", {
  fake <- fakeRunner()
  withr::local_options(rmeds.runner = fake$runner)
  root <- withr::local_tempdir()
  fake$runner("medsDevEvaluation", hydraOverrides(output_dir = root), character(), NULL, FALSE)
  evaluation <- readEvaluation(root)
  preflight <- structure(list(
    tables = data.frame(table = c("measurement", "death"), rows = c(100, 3), unmappedShare = c(0.1, 0), midnightShare = NA_real_, missingUnitShare = NA_real_),
    vocabularyVersion = "v5", cdmVersion = "5.4"
  ), class = "mappingPreflight")

  files <- exportResults(evaluation, preflight, file.path(root, "export"), minCellCount = 5, databaseId = "site_a")

  shared <- utils::read.csv(files[["evaluation"]])
  expect_true(is.na(shared$value[shared$metric == "samples_equally_weighted/n_samples"]))
  expect_equal(shared$value[shared$metric == "samples_equally_weighted/roc_auc_score"], 0.81)
  tables <- utils::read.csv(files[["preflight"]])
  expect_true(is.na(tables$rows[tables$table == "death"]))
  expect_equal(tables$rows[tables$table == "measurement"], 100)
  expect_equal(jsonlite::read_json(files[["metadata"]])$databaseId, "site_a")
})
