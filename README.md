# rmeds

Run the OMOP-to-MEDS ETL ([OMOP_MEDS](https://github.com/rvandewater/OMOP_MEDS)) and
[MEDS-DEV](https://github.com/mmcdermott/MEDS-DEV) benchmarks on your own OMOP CDM
from R, the way OHDSI analysts already work: a database connection in, typed R
objects and shareable aggregate results out.

> Status: initial prototype (0.0.0.9000). The full pipeline has run end to end
> against the real tools (OMOP_MEDS 0.4.0, MEDS-DEV 0.1.0, Python 3.12, macOS)
> on a small synthetic CDM, with `random_predictor` as the model. It has not yet
> been run on a real OMOP database, on Windows, or with the trained models.

## Quick start

```r
# remotes::install_github("rvandewater/rmeds")
library(rmeds)

setupPythonEnvironment()   # pinned OMOP_MEDS + MEDS-DEV env via reticulate/uv

connectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms = "postgresql", server = "host/db", user = "me",
  password = keyring::key_get("cdm")
)

omop <- exportCdmToParquet(connectionDetails,
                           cdmDatabaseSchema = "cdm",
                           outputFolder = "work/omop")

preflight <- runMappingPreflight(omop)   # aggregate mapping-quality report
preflight

meds    <- runOmopToMeds(omop, outputFolder = "work/meds")
labels  <- extractTaskLabels(meds, task = "mortality/in_icu/first_24h",
                             outputFolder = "work/labels",
                             predicatesPath = "omop_predicates.yaml")
run     <- runMedsDevModel(meds, labels, model = "random_predictor",
                           outputFolder = "work/models/random_predictor")
results <- evaluatePredictions(run)

exportResults(results, preflight, outputFolder = "work/share",
              minCellCount = 5, databaseId = "my_site")
```

Any DBI connection works too (`exportCdmToParquet(connection = con, ...)`), and
every step also accepts a path instead of the previous step's object, so you can
start from an existing CSV/Parquet dump or MEDS dataset.

## Design

One file per pipeline stage; each holds the step function and the object it
returns. Stages meet only through small S3 objects that wrap a folder
(`omopSource`, `medsDataset`, `medsLabels`, `medsModelRun`) and `as*()`
coercers, so steps never depend on how their input was produced.

| File | Responsibility | Talks to |
| --- | --- | --- |
| `python-env.R` | Pinned Python requirements, console-script lookup | reticulate |
| `runner.R` | Running a tool: process, `PATH`, logs, errors, Hydra overrides | processx |
| `omop-source.R` | CDM export to Parquet; `omopSource` | DBI / DatabaseConnector, arrow |
| `preflight.R` | Aggregate mapping-quality report (measures, never changes data) | arrow, dplyr |
| `meds-dataset.R` | OMOP to MEDS; `medsDataset` | runner |
| `labels.R` | MEDS-DEV task labels; `medsLabels` | runner |
| `models.R` | MEDS-DEV train/predict; `medsModelRun` | runner |
| `evaluation.R` | MEDS-DEV evaluation; `medsEvaluation` | runner |
| `results.R` | Small-cell-suppressed export for sharing | - |
| `catalog.R` | List MEDS-DEV tasks, models, datasets in-process | reticulate |

Python runs in two ways, both from the same environment:

* **Frontend (in-process, reticulate):** quick lookups such as
  `listMedsDevTasks()` and `pythonEnvironmentInfo()`.
* **Backend (separate processes, processx):** every long-running stage, so a
  crash or out-of-memory error in the ETL never takes down the R session.
  MEDS-DEV builds a separate temporary environment for each model itself.

## Python environment

`rmeds` declares `OMOP_MEDS==0.4.0` and `MEDS-DEV==0.1.0` (Python >= 3.12, < 3.14)
with `reticulate::py_require()` when it loads. On first use reticulate has uv
build a cached environment. For offline sites, pre-build an environment and set
`options(rmeds.python = "/path/to/env/bin/python")`, or set `UV_OFFLINE=1`.

## Known limitations

* MEDS-DEV has no OMOP dataset entry yet; pass your own ACES predicates file
  (`predicatesPath`) written in the codes your MEDS data uses.
* MEDS-DEV builds shell commands from paths; keep work folders free of spaces.
* No harmonisation of codes, units or hierarchies across sites (by design for
  now); `runMappingPreflight()` only reports.
* No Strategus module yet.

## Development

```r
devtools::test()     # synthetic data and a fake tool runner, no Python needed
```

Set `RMEDS_INTEGRATION=true` to also run the end-to-end test against the real
Python tools (downloads the pinned packages on first use).
