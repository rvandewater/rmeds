# The full rmeds pipeline on the public MIMIC-IV OMOP demo:
#   demo("mimic-iv-omop", package = "rmeds")
#
# Downloads the PhysioNet project "MIMIC-IV demo data in the OMOP Common Data
# Model" v0.9 (open access, ODbL, ~11 MB zip, 100 patients) into a work folder,
# converts it to MEDS, labels the MEDS-DEV hyponatremia task, runs
# random_predictor and evaluates it. Set RMEDS_DEMO_DIR to choose the folder
# (keep it free of spaces: MEDS-DEV builds shell commands from paths).
#
# The demo ships only MIMIC's own source concepts, not the standard OMOP
# vocabularies, so its MEDS codes are source codes (mimiciv_*) or OMOP_MEDS
# placeholders. The predicates file is written for those codes; a site with a
# full vocabulary would use LOINC codes instead. With 100 patients the held-out
# split has about 10 subjects, so expect undefined AUROC.

library(rmeds)
setupPythonEnvironment()

work <- Sys.getenv("RMEDS_DEMO_DIR", file.path(tempdir(), "rmeds-mimic-demo"))
dir.create(work, recursive = TRUE, showWarnings = FALSE)

zip <- file.path(work, "mimic-iv-demo-omop-0.9.zip")
if (!file.exists(zip)) {
  utils::download.file("https://physionet.org/content/mimic-iv-demo-omop/get-zip/0.9/", zip, mode = "wb")
}
csv <- grep("/1_omop_data_csv/[^/]+\\.csv$", utils::unzip(zip, list = TRUE)$Name, value = TRUE)
utils::unzip(zip, files = csv, exdir = file.path(work, "omop"), junkpaths = TRUE, overwrite = TRUE)

# The demo's vocabulary files are named 2b_concept.csv etc.; omopSource()
# recognises them.
omop <- omopSource(file.path(work, "omop"))
preflight <- runMappingPreflight(omop)
preflight

meds <- runOmopToMeds(omop, file.path(work, "meds"),
                      datasetName = "MIMIC_IV_OMOP_DEMO", omopVersion = "5.3",
                      overwrite = TRUE)
summary(meds)

predicates <- file.path(work, "predicates.yaml")
file.copy(system.file("predicates", "mimic-iv-omop-demo.yaml", package = "rmeds"),
          predicates, overwrite = TRUE)
labels <- extractTaskLabels(meds, "abnormal_lab/blood_chemistry/hyponatremia/first_24h",
                            file.path(work, "labels"),
                            dataset = "MIMIC_IV_OMOP_DEMO",
                            predicatesPath = predicates, overwrite = TRUE)
summary(labels)

run <- runMedsDevModel(meds, labels, model = "random_predictor",
                       outputFolder = file.path(work, "model"), overwrite = TRUE)
evaluation <- evaluatePredictions(run)
evaluation

exportResults(evaluation, preflight, file.path(work, "share"),
              minCellCount = 5, databaseId = "mimic_iv_omop_demo")
