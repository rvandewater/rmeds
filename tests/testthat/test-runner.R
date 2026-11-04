# Exercises the real process runner against stand-in console scripts.

fakePythonEnv <- function(script, body) {
  bin <- withr::local_tempdir(.local_envir = parent.frame())
  file.create(file.path(bin, "python"))
  path <- file.path(bin, script)
  writeLines(c("#!/bin/sh", body), path)
  Sys.chmod(path, "0755")
  file.path(bin, "python")
}

test_that("processRunner runs the tool, logs output and puts the env first on PATH", {
  skip_on_os("windows")
  python <- fakePythonEnv("meds-dev-evaluation", c("echo \"args: $@\"", "echo \"path: $PATH\""))
  withr::local_options(rmeds.python = python, rmeds.runner = NULL)
  logFile <- file.path(withr::local_tempdir(), "logs", "tool.log")

  result <- runPythonTool("medsDevEvaluation", args = c("a=1", "b='x y'"), logFile = logFile, verbose = FALSE)

  expect_equal(result$status, 0)
  log <- readLines(logFile)
  expect_true(any(grepl("args: a=1 b='x y'", log, fixed = TRUE)))
  expect_true(any(startsWith(log, paste0("path: ", dirname(python)))))
})

test_that("processRunner fails with the tail of the tool output", {
  skip_on_os("windows")
  python <- fakePythonEnv("OMOP_MEDS", c("echo 'stage pre_MEDS failed: bad schema'", "exit 3"))
  withr::local_options(rmeds.python = python, rmeds.runner = NULL)

  expect_error(
    runPythonTool("omopToMeds", verbose = FALSE),
    "exited with status 3(.|\n)*bad schema"
  )
})

test_that("a missing console script points to setupPythonEnvironment", {
  withr::local_options(rmeds.python = file.path(withr::local_tempdir(), "python"), rmeds.runner = NULL)
  expect_error(runPythonTool("medsDevTask", verbose = FALSE), "setupPythonEnvironment")
})
