# Stage: shareable results. Writes only aggregates, after small-cell
# suppression, so the folder can leave the site.

#' Export aggregate results for sharing
#'
#' Writes `evaluation.csv`, `preflight.csv` (when given) and `metadata.json`
#' to `outputFolder`. Counts below `minCellCount` are replaced by `NA`, along
#' with the shares computed from them.
#'
#' @param evaluation A `medsEvaluation` from [evaluatePredictions()].
#' @param preflight Optional `mappingPreflight` from [runMappingPreflight()].
#' @param outputFolder Folder to write to.
#' @param minCellCount Smallest count that may be shared.
#' @param databaseId Identifier for the data source, stored with every row.
#'
#' @return The written file paths, invisibly.
#' @export
exportResults <- function(evaluation,
                          preflight = NULL,
                          outputFolder,
                          minCellCount = 5,
                          databaseId = "unknown") {
  if (!inherits(evaluation, "medsEvaluation")) {
    cli::cli_abort("{.arg evaluation} must be a {.cls medsEvaluation}.")
  }
  outputFolder <- prepareOutputFolder(outputFolder)
  files <- c(
    evaluation = file.path(outputFolder, "evaluation.csv"),
    metadata = file.path(outputFolder, "metadata.json")
  )

  metrics <- as.data.frame(unclass(evaluation)[c("metric", "value")])
  metrics$value <- suppressCounts(metrics$value, isCountMetric(metrics$metric), minCellCount)
  utils::write.csv(cbind(databaseId = databaseId, metrics), files[["evaluation"]], row.names = FALSE)

  if (!is.null(preflight)) {
    files[["preflight"]] <- file.path(outputFolder, "preflight.csv")
    tables <- preflight$tables
    small <- !is.na(tables$rows) & tables$rows < minCellCount
    tables[small, setdiff(names(tables), "table")] <- NA
    utils::write.csv(cbind(databaseId = databaseId, tables), files[["preflight"]], row.names = FALSE)
  }

  jsonlite::write_json(
    list(
      databaseId = databaseId,
      rmedsVersion = as.character(utils::packageVersion("rmeds")),
      pythonRequirements = pythonRequirements(),
      vocabularyVersion = preflight$vocabularyVersion,
      cdmVersion = preflight$cdmVersion,
      minCellCount = minCellCount,
      exportedAt = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    ),
    files[["metadata"]],
    auto_unbox = TRUE,
    pretty = TRUE
  )
  invisible(files)
}

isCountMetric <- function(metric) {
  grepl("(^|/)(n|count|num)_|_count$|(^|/)n$", metric)
}

suppressCounts <- function(value, isCount, minCellCount) {
  value[isCount & !is.na(value) & value < minCellCount] <- NA
  value
}
