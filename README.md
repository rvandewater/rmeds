# rMEDS

<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/rvandewater/rmeds/actions/workflows/R-CMD-check.yaml/badge.svg?branch=main&event=push)](https://github.com/rvandewater/rmeds/actions/workflows/R-CMD-check.yaml)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
<!-- badges: end -->
> [!WARNING]
> This package is in very early development.

## Overview

rMEDS runs the OMOP-to-MEDS ETL ([OMOP_MEDS](https://github.com/rvandewater/OMOP_MEDS)) and
[MEDS-DEV](https://github.com/Medical-Event-Data-Standard/MEDS-DEV) benchmarks on your own OMOP CDM
from R, the way OHDSI analysts already work: a database connection in, typed R
objects and shareable aggregate results out. The R package is called `rmeds`.

> Status: initial prototype (0.0.0.9000). The full pipeline has run end to end
> against the real tools (OMOP_MEDS 0.4.0, MEDS-DEV 0.1.0, Python 3.12, macOS)
> on a synthetic CDM and on the public MIMIC-IV OMOP demo (100 patients), with
> `random_predictor` and the trained `meds_tab/tiny`. It has not yet been run on
> a full-size OMOP database, and on Windows only the unit tests have run.
> Function names and outputs may still change.

## Installation

rMEDS is not on CRAN. Install the development version from GitHub:

```r
# install.packages("pak")
pak::pak("rvandewater/rmeds")
```

To connect with OHDSI `connectionDetails`, also install
[DatabaseConnector](https://github.com/OHDSI/DatabaseConnector); any other DBI
connection (e.g. duckdb) works without it.

### Python

The ETL and the benchmarks are Python tools. rMEDS declares
`OMOP_MEDS==0.4.0` and `MEDS-DEV==0.1.0` (Python >= 3.12, < 3.14) with
`reticulate::py_require()` when it loads, and on first use reticulate has
[uv](https://docs.astral.sh/uv/) build a cached environment. Nothing needs to be
installed by hand:

```r
library(rmeds)
setupPythonEnvironment()   # build the environment now rather than on first use
pythonEnvironmentInfo()    # the Python and tool versions in use
```

To manage the environment yourself, for example to pre-build one for a site
without internet access, create it with uv and point rmeds at it:

```bash
uv venv ~/.venvs/rmeds --python 3.12
uv pip install --python ~/.venvs/rmeds OMOP_MEDS==0.4.0 MEDS-DEV==0.1.0
```

```r
options(rmeds.python = path.expand("~/.venvs/rmeds/bin/python"))
setupPythonEnvironment()   # checks that the environment has every tool rmeds runs
```

To keep reticulate's own environment but resolve it from the uv cache only,
set `UV_OFFLINE=1`.

## Getting started

```r
library(rmeds)

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

rmeds functions follow the pipeline:

* **OMOP CDM:** `exportCdmToParquet()` exports CDM tables from a database;
  `omopSource()` wraps an existing folder of CSV or Parquet tables, and
  `openOmopTable()` opens one table as an Arrow dataset.
* **Mapping quality:** `runMappingPreflight()` reports, per table, the share of
  rows without a standard concept, concept ids missing from the vocabulary,
  midnight timestamps and measurements without units, as aggregate shares
  only.
* **MEDS:** `runOmopToMeds()` runs the ETL; `medsData()`, `medsCodes()`,
  `medsSubjectSplits()` and `medsMetadata()` read the result.
* **Tasks and models:** `listMedsDevTasks()` and `listMedsDevModels()` list
  what MEDS-DEV offers; `extractTaskLabels()` labels a task and
  `runMedsDevModel()` trains a model and predicts.
* **Evaluation and sharing:** `evaluatePredictions()` scores the predictions
  and `exportResults()` writes the metrics and pre-flight report with
  small-cell suppression, ready to share in a network study.

## Try it on public data

```r
demo("mimic-iv-omop", package = "rmeds")
```

This downloads the PhysioNet
[MIMIC-IV demo in OMOP](https://physionet.org/content/mimic-iv-demo-omop/0.9/)
(open access, ~11 MB), converts it to MEDS, labels the MEDS-DEV task
`abnormal_lab/blood_chemistry/hyponatremia/first_24h` with the predicates in
`inst/predicates/mimic-iv-omop-demo.yaml`, and runs and evaluates
`random_predictor` (about 20 seconds once the Python environment exists).

To go through it step by step, open the Jupyter notebook
[`notebooks/mimic-iv-omop-demo.ipynb`](notebooks/mimic-iv-omop-demo.ipynb)
(R kernel, [IRkernel](https://github.com/IRkernel/IRkernel)). It runs the
same pipeline one cell at a time, with explanations and aggregate outputs
only: the OMOP tables, the pre-flight report, the MEDS code vocabularies, the
labels per split, the metrics, and optionally a trained `meds_tab/tiny` model.
The saved outputs show what to expect before you run anything.

Jupyter itself does not need installing; [uv](https://docs.astral.sh/uv/)
can run it on demand. Install and register the R kernel once:

```r
install.packages("IRkernel")
```

```bash
uv run --no-project --with jupyter-client -- Rscript -e 'IRkernel::installspec()'
```

Then, from the repository folder, open the notebook in JupyterLab, or run all
of it without a browser and save the outputs in the file:

```bash
uvx --from jupyterlab jupyter-lab notebooks/mimic-iv-omop-demo.ipynb
uvx --from nbconvert jupyter-nbconvert --to notebook --execute --inplace notebooks/mimic-iv-omop-demo.ipynb
```

Set `RMEDS_DEMO_DIR` to a folder without spaces to keep the downloaded data
between runs.

Two things to expect:

* The demo ships only MIMIC's own source concepts, not the standard OMOP
  vocabularies, so `runMappingPreflight()` reports nearly every concept id as
  not in the vocabulary, and the MEDS codes are MIMIC source codes or
  `OMOP_<table>//...` placeholders rather than `LOINC//...`. A real site with a
  full vocabulary export gets standard codes; the
  [Eunomia](https://github.com/OHDSI/EunomiaDatasets) Synthea sets do too.
* With 100 patients the held-out split has about 10 subjects and no positive
  labels, so AUROC is undefined and `evaluatePredictions()` warns.

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

## Known limitations

* MEDS-DEV has no OMOP dataset entry yet; pass your own ACES predicates file
  (`predicatesPath`) written in the codes your MEDS data uses.
* OMOP_MEDS 0.4.0 does not convert `visit_detail`, where OMOP keeps ICU stays,
  so ICU-level tasks such as `mortality/in_icu/first_24h` cannot be defined on
  real ICU stays yet. Hospital-level tasks (the `abnormal_lab` family) work.
* MEDS-DEV builds shell commands from paths; keep work folders free of spaces.
* No harmonisation of codes, units or hierarchies across sites (by design for
  now); `runMappingPreflight()` only reports.
* No Strategus module yet.

## Related work

* [MEDS](https://github.com/Medical-Event-Data-Standard/meds), the Medical
  Event Data Standard that rMEDS produces.
* [OMOP_MEDS](https://github.com/rvandewater/OMOP_MEDS), the OMOP-to-MEDS ETL
  rMEDS runs.
* [MEDS-DEV](https://github.com/Medical-Event-Data-Standard/MEDS-DEV), the benchmark of tasks,
  models and evaluation rMEDS runs on the result. Its tasks are defined in
  [ACES](https://github.com/justin13601/ACES), which is also the language of
  the predicates files.
* [PatientLevelPrediction](https://github.com/OHDSI/PatientLevelPrediction),
  OHDSI's R package for prediction models built directly on the CDM. rMEDS
  complements it: the same CDM can be run through MEDS-DEV's shared tasks and
  models and compared with MEDS datasets from outside OHDSI.
* [Strategus](https://github.com/OHDSI/Strategus), OHDSI's framework for
  network studies, which a future rMEDS module would plug into.

## Getting help

If you find a bug, please file a minimal reproducible example on
[GitHub](https://github.com/rvandewater/rmeds/issues), with the output of
`pythonEnvironmentInfo()`. **Never include patient-level data in an issue:**
share the output of `runMappingPreflight()` or `exportResults()` instead, or
reproduce the problem on the public MIMIC-IV demo with
`demo("mimic-iv-omop", package = "rmeds")`.

Problems in the ETL or the benchmark themselves belong in the
[OMOP_MEDS](https://github.com/rvandewater/OMOP_MEDS/issues) or
[MEDS-DEV](https://github.com/Medical-Event-Data-Standard/MEDS-DEV/issues) issue trackers. For
questions about OMOP CDM mapping, use the [OHDSI forums](https://forums.ohdsi.org).

## Development

```r
devtools::test()     # synthetic data and a fake tool runner, no Python needed
```

Set `RMEDS_INTEGRATION=true` to also run the end-to-end test against the real
Python tools (downloads the pinned packages on first use). GitHub Actions runs
`R CMD check` on Linux and Windows for every pull request and push to main,
and on macOS too every Monday and on demand (Actions > R-CMD-check > Run
workflow), because hosted macOS runners are often unavailable at busy times.

## License

Apache License 2.0; see [LICENSE](LICENSE).

---

Please note that the rMEDS project is released with a
[Contributor Code of Conduct](.github/CODE_OF_CONDUCT.md). By contributing to
this project, you agree to abide by its terms.
