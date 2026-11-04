# rmeds 0.0.0.9000

* Initial prototype: CDM export to Parquet, mapping pre-flight, OMOP_MEDS ETL, MEDS-DEV task labels, models and evaluation, and small-cell-suppressed result export.

## Fixes and additions from running the MIMIC-IV OMOP demo and Synthea

* `demo("mimic-iv-omop")` runs the whole pipeline on the public PhysioNet MIMIC-IV OMOP demo, with predicates for its codes in `inst/predicates/`.
* `runMappingPreflight()` reports `notInVocabularyShare`: rows whose concept id is not in the exported `concept` table, which OMOP_MEDS cannot turn into standard codes.
* CSV tables are read with types from the CDM naming conventions instead of Arrow's first-block inference, which failed on columns that start empty or start numeric.
* `omopSource()` drops the MIMIC demo's `2b_` file prefix, and `runOmopToMeds()` gives OMOP_MEDS lower-case table names (it failed on Eunomia's `CONCEPT.csv`) and stops early if `person`, `concept` or `concept_relationship` is missing.
* `readEvaluation()` reads the `NaN` metrics MEDS-Evaluation writes (e.g. AUROC with one class) as `NA`, and `evaluatePredictions()` warns about them.

## Documentation

* The README follows the usual R package layout: badges, installation, getting started, related work, getting help, and a code of conduct. The repository now includes the Apache 2.0 `LICENSE` text.
* `notebooks/mimic-iv-omop-demo.ipynb` walks through the MIMIC-IV OMOP demo step by step in Jupyter (R kernel), with saved aggregate outputs.
* The README shows how to run the notebook with Jupyter from uv, and how to point rmeds at a Python environment built with uv.
