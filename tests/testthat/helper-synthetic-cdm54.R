# A fuller synthetic OMOP CDM 5.4 (made-up data) for the end-to-end test.
# syntheticCdmDuckdb() returns an open DuckDB connection with schema 'cdm'.

syntheticCdmDuckdb <- function(nPersons = 40, seed = 1) {
  withr::local_seed(seed)
  con <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbExecute(con, "CREATE SCHEMA cdm")
  w <- function(table, data) DBI::dbWriteTable(con, DBI::Id(schema = "cdm", table = table), data)
  ts <- function(x) as.POSIXct(x, origin = "1970-01-01", tz = "UTC")
  ids <- seq_len(nPersons)
  birth <- as.Date("1940-01-01") + sample(0:20000, nPersons)
  start <- as.Date("2015-01-01") + sample(0:1500, nPersons)
  w("person", data.frame(
    person_id = ids, gender_concept_id = sample(c(8507L, 8532L), nPersons, TRUE),
    year_of_birth = as.integer(format(birth, "%Y")), month_of_birth = as.integer(format(birth, "%m")),
    day_of_birth = as.integer(format(birth, "%d")), birth_datetime = ts(as.POSIXct(birth)),
    race_concept_id = 8527L, ethnicity_concept_id = 38003564L,
    location_id = NA_integer_, provider_id = NA_integer_, care_site_id = NA_integer_,
    person_source_value = as.character(ids), gender_source_value = "U", gender_source_concept_id = 0L,
    race_source_value = "", race_source_concept_id = 0L, ethnicity_source_value = "", ethnicity_source_concept_id = 0L
  ))
  w("observation_period", data.frame(
    observation_period_id = ids, person_id = ids, observation_period_start_date = start,
    observation_period_end_date = start + 400, period_type_concept_id = 32817L
  ))
  visitStart <- ts(as.POSIXct(start + 30) + 3600 * 9)
  w("visit_occurrence", data.frame(
    visit_occurrence_id = ids, person_id = ids, visit_concept_id = sample(c(9201L, 262L), nPersons, TRUE),
    visit_start_date = as.Date(visitStart), visit_start_datetime = visitStart,
    visit_end_date = as.Date(visitStart) + 5, visit_end_datetime = visitStart + 5 * 86400,
    visit_type_concept_id = 32817L, provider_id = NA_integer_, care_site_id = NA_integer_,
    visit_source_value = "IP", visit_source_concept_id = 0L, admitted_from_concept_id = 0L,
    admitted_from_source_value = "", discharged_to_concept_id = 0L, discharged_to_source_value = "",
    preceding_visit_occurrence_id = NA_integer_
  ))
  nCond <- nPersons * 2
  condPerson <- rep(ids, 2)
  condStart <- visitStart[condPerson] + 3600
  w("condition_occurrence", data.frame(
    condition_occurrence_id = seq_len(nCond), person_id = condPerson,
    condition_concept_id = sample(c(201826L, 316866L, 0L), nCond, TRUE),
    condition_start_date = as.Date(condStart), condition_start_datetime = condStart,
    condition_end_date = as.Date(NA), condition_end_datetime = ts(NA), condition_type_concept_id = 32817L,
    condition_status_concept_id = 0L, stop_reason = NA_character_, provider_id = NA_integer_,
    visit_occurrence_id = condPerson, visit_detail_id = NA_integer_, condition_source_value = "X",
    condition_source_concept_id = 0L, condition_status_source_value = NA_character_
  ))
  nMeas <- nPersons * 6
  measPerson <- rep(ids, 6)
  measTime <- visitStart[measPerson] + sample(1:40, nMeas, TRUE) * 3600
  measConcept <- sample(c(3016723L, 3019550L), nMeas, TRUE)
  w("measurement", data.frame(
    measurement_id = seq_len(nMeas), person_id = measPerson, measurement_concept_id = measConcept,
    measurement_date = as.Date(measTime), measurement_datetime = measTime, measurement_time = NA_character_,
    measurement_type_concept_id = 32817L, operator_concept_id = 0L,
    value_as_number = ifelse(measConcept == 3016723L, round(rnorm(nMeas, 1.1, 0.4), 2), round(rnorm(nMeas, 138, 4))),
    value_as_concept_id = 0L, unit_concept_id = ifelse(measConcept == 3016723L, 8840L, 9557L),
    range_low = NA_real_, range_high = NA_real_, provider_id = NA_integer_, visit_occurrence_id = measPerson,
    visit_detail_id = NA_integer_, measurement_source_value = "lab", measurement_source_concept_id = 0L,
    unit_source_value = "", unit_source_concept_id = 0L, value_source_value = "",
    measurement_event_id = NA_integer_, meas_event_field_concept_id = 0L
  ))
  dead <- sample(ids, nPersons %/% 5)
  w("death", data.frame(
    person_id = dead, death_date = as.Date(visitStart[dead]) + 3, death_datetime = visitStart[dead] + 3 * 86400,
    death_type_concept_id = 32817L, cause_concept_id = 0L, cause_source_value = "", cause_source_concept_id = 0L
  ))
  concepts <- data.frame(
    concept_id = c(8507L, 8532L, 8527L, 38003564L, 9201L, 262L, 201826L, 316866L, 3016723L, 3019550L, 8840L, 9557L, 32817L, 0L),
    concept_name = c("MALE", "FEMALE", "White", "Not Hispanic or Latino", "Inpatient Visit", "Emergency Room and Inpatient Visit",
                     "Type 2 diabetes mellitus", "Hypertensive disorder", "Creatinine [Mass/volume] in Serum or Plasma",
                     "Sodium [Moles/volume] in Serum or Plasma", "milligram per deciliter", "milliequivalent per liter", "EHR", "No matching concept"),
    domain_id = c("Gender", "Gender", "Race", "Ethnicity", "Visit", "Visit", "Condition", "Condition", "Measurement", "Measurement", "Unit", "Unit", "Type Concept", "Metadata"),
    vocabulary_id = c("Gender", "Gender", "Race", "Ethnicity", "Visit", "Visit", "SNOMED", "SNOMED", "LOINC", "LOINC", "UCUM", "UCUM", "Type Concept", "None"),
    concept_class_id = "Concept", standard_concept = c(rep("S", 13), NA),
    concept_code = c("M", "F", "5", "Not Hispanic", "IP", "ERIP", "44054006", "38341003", "2160-0", "2951-2", "mg/dL", "meq/L", "32817", "No matching concept"),
    valid_start_date = as.Date("1970-01-01"), valid_end_date = as.Date("2099-12-31"), invalid_reason = NA_character_
  )
  w("concept", concepts)
  w("concept_relationship", data.frame(
    concept_id_1 = concepts$concept_id, concept_id_2 = concepts$concept_id, relationship_id = "Maps to",
    valid_start_date = as.Date("1970-01-01"), valid_end_date = as.Date("2099-12-31"), invalid_reason = NA_character_
  ))
  w("vocabulary", data.frame(vocabulary_id = "None", vocabulary_name = "OMOP Standardized Vocabularies",
                             vocabulary_reference = "synthetic", vocabulary_version = "synthetic-2026", vocabulary_concept_id = 44819096L))
  w("cdm_source", data.frame(cdm_source_name = "synthetic", cdm_source_abbreviation = "SYN", cdm_holder = "rmeds",
                             source_description = "synthetic", source_documentation_reference = "", cdm_etl_reference = "",
                             source_release_date = as.Date("2026-11-01"), cdm_release_date = as.Date("2026-11-01"),
                             cdm_version = "5.4", cdm_version_concept_id = 756265L, vocabulary_version = "synthetic-2026"))
  con
}
