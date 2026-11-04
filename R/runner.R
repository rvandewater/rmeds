# Every Python process starts here. Steps describe *what* to run (a tool name
# and Hydra overrides); this file decides *how*. Swap the runner with
# options(rmeds.runner = fn) to test steps without Python.

#' Run one of the pinned Python tools in a separate process
#'
#' Resolves the tool's console script in the rmeds Python environment, puts
#' that environment first on `PATH` (MEDS-DEV shells out to `aces-cli` and
#' friends), streams output to the console and to `logFile`, and fails with
#' the tail of the log when the tool exits non-zero.
#'
#' @param tool One of `"omopToMeds"`, `"medsDevTask"`, `"medsDevModel"`,
#'   `"medsDevEvaluation"`.
#' @param args Character vector of command-line arguments, usually from
#'   [hydraOverrides()].
#' @param env Named character vector of extra environment variables.
#' @param logFile File to write the tool's combined output to, or `NULL`.
#' @param verbose Echo the tool's output to the console.
#'
#' @return A list describing the run, invisibly.
#' @export
runPythonTool <- function(tool,
                          args = character(),
                          env = character(),
                          logFile = NULL,
                          verbose = getOption("rmeds.verbose", TRUE)) {
  tool <- rlang::arg_match(tool, names(pythonTools))
  runner <- getOption("rmeds.runner", default = processRunner)
  runner(tool = tool, args = args, env = env, logFile = logFile, verbose = verbose)
}

processRunner <- function(tool, args, env, logFile, verbose) {
  command <- pythonToolPath(tool)
  path <- paste(dirname(command), Sys.getenv("PATH"), sep = .Platform$path.sep)
  log <- NULL
  if (!is.null(logFile)) {
    dir.create(dirname(logFile), recursive = TRUE, showWarnings = FALSE)
    log <- file(logFile, open = "w")
    on.exit(close(log), add = TRUE)
    cat("$", command, paste(shQuote(args), collapse = " "), "\n", file = log)
  }
  echo <- function(chunk, process) {
    if (!is.null(log)) cat(chunk, file = log)
    if (verbose) cat(chunk)
  }
  result <- processx::run(
    command,
    args,
    env = c("current", PATH = path, env),
    error_on_status = FALSE,
    stderr_to_stdout = TRUE,
    stdout_callback = echo,
    cleanup_tree = TRUE
  )
  if (result$status != 0) {
    lastLines <- utils::tail(strsplit(result$stdout, "\n", fixed = TRUE)[[1]], 20)
    rlang::abort(paste(c(
      sprintf("`%s` exited with status %d. Last output:", pythonTools[[tool]], result$status),
      lastLines,
      if (!is.null(logFile)) sprintf("Full log: %s", logFile)
    ), collapse = "\n"))
  }
  invisible(list(tool = tool, command = command, args = args, status = result$status, logFile = logFile))
}

#' Build Hydra command-line overrides from R values
#'
#' `NULL` values are dropped, logicals become `true`/`false`, vectors become
#' Hydra lists, and values Hydra would misparse are single-quoted. Prefix a
#' name with `++` to add a key that may not exist in the tool's config.
#'
#' @param ... Named values.
#'
#' @return A character vector of `key=value` arguments.
#' @export
#' @examples
#' hydraOverrides(task = "mortality/in_icu/first_24h", do_overwrite = FALSE,
#'                "++dataset_predicates_path" = "/data/predicates.yaml")
hydraOverrides <- function(...) {
  values <- list(...)
  values <- values[!vapply(values, is.null, logical(1))]
  if (length(values) == 0) {
    return(character())
  }
  if (is.null(names(values)) || any(names(values) == "")) {
    cli::cli_abort("All Hydra overrides must be named.")
  }
  vapply(
    names(values),
    function(key) paste0(key, "=", formatHydraValue(values[[key]])),
    character(1),
    USE.NAMES = FALSE
  )
}

formatHydraValue <- function(value) {
  if (length(value) != 1) {
    return(paste0("[", paste(vapply(value, formatHydraValue, character(1)), collapse = ","), "]"))
  }
  if (is.logical(value)) {
    return(if (isTRUE(value)) "true" else "false")
  }
  if (is.numeric(value)) {
    return(format(value, scientific = FALSE, trim = TRUE))
  }
  value <- as.character(value)
  if (grepl("^[A-Za-z0-9_/.:+~-]+$", value)) {
    return(value)
  }
  paste0("'", gsub("'", "\\\\'", value), "'")
}

# MEDS-DEV assembles shell command strings from config values, so paths with
# spaces or shell metacharacters break inside it no matter how we quote them.
checkShellSafePaths <- function(...) {
  paths <- unlist(list(...))
  unsafe <- paths[grepl("[[:space:]'\"$`;&|<>()]", paths)]
  if (length(unsafe) > 0) {
    cli::cli_warn(c(
      "MEDS-DEV builds shell commands from these paths, which contain spaces or shell characters:",
      stats::setNames(unsafe, rep("*", length(unsafe))),
      i = "Use paths without spaces if the step fails."
    ))
  }
  invisible(paths)
}
