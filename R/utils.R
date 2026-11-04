# Small filesystem helpers shared by the pipeline steps.

prepareOutputFolder <- function(outputFolder, overwrite = FALSE) {
  if (overwrite && dir.exists(outputFolder)) {
    unlink(outputFolder, recursive = TRUE)
  }
  dir.create(outputFolder, recursive = TRUE, showWarnings = FALSE)
  normalizePath(outputFolder, winslash = "/", mustWork = TRUE)
}

existingFolder <- function(path, what) {
  if (!is.character(path) || length(path) != 1 || !dir.exists(path)) {
    cli::cli_abort("{what} folder {.file {path}} does not exist.")
  }
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

# Files below `path`, skipping hidden folders such as .logs and .venv.
visibleFiles <- function(path, pattern) {
  files <- list.files(path, pattern = pattern, recursive = TRUE, full.names = TRUE)
  relative <- substring(files, nchar(path) + 2)
  files[!grepl("(^|/)\\.", relative)]
}

`%||%` <- function(x, y) if (is.null(x)) y else x
