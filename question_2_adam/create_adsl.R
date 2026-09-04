# ------------------------------------------------------------------------------
# Title:   Question 2 - Create the ADaM Subject Level Analysis Dataset (ADSL)
#
# Purpose: Build ADSL from SDTM source data using the {admiral} family of
#          packages and tidyverse tools, with DM as the basis, and derive the
#          four additional variables requested in the assessment.
#
# Input dataset(s):
#   - pharmaversesdtm::dm   basis of ADSL, one record per subject
#   - pharmaversesdtm::ex   exposure (TRTSDTM / TRTSTMF, and one LSTAVLDT source)
#   - pharmaversesdtm::vs   vital signs   (LSTAVLDT source)
#   - pharmaversesdtm::ae   adverse events (LSTAVLDT source)
#   - pharmaversesdtm::ds   disposition    (LSTAVLDT source)
#
# Output(s):
#   - question_2_adam/adsl.csv    ADSL, one row per subject, with:
#       AGEGR9, AGEGR9N   age groups "<18" / "18 - 50" / ">50" (1 / 2 / 3)
#       TRTSDTM, TRTSTMF  first valid-dose exposure datetime + imputation flag
#       ITTFL             "Y"/"N" - ARM populated in DM
#       LSTAVLDT          last known alive date (VS / AE / DS / EX sources)
#   - question_2_adam/run_log.txt  console log proving an error-free run
#
# SCOPE: DM as the base plus exactly the four requested derivations and the
#        intermediates they need. The full {admiral} ADSL vignette also builds
#        TRTEDTM, TRTDURD, SAFFL and the death variables; those are not asked for
#        here, so they are deliberately left out rather than carried along as
#        unrequested scope.
#
# Author: Maksim Sendetski
# Date:   2026-09-04
# ------------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(admiral)
  library(dplyr)
  library(stringr)
})

# Warnings are deferred and collected so section 7 can assert the run was clean.
# Set explicitly rather than relying on the default, so the assertion means the
# same thing under Rscript and inside an RStudio session with its own options.
options(warn = 0)

# ------------------------------------------------------------------------------
# 1. Source data
# ------------------------------------------------------------------------------

dm <- pharmaversesdtm::dm
ex <- pharmaversesdtm::ex
vs <- pharmaversesdtm::vs
ae <- pharmaversesdtm::ae
ds <- pharmaversesdtm::ds

cat("Subjects in DM:", nrow(dm), "\n\n")

# DM is one record per subject, so it is the ADSL skeleton: every derivation
# below merges onto it and must not change the row count.
adsl <- dm

# ------------------------------------------------------------------------------
# 2. AGEGR9 / AGEGR9N - analysis age group
#
# Boundary reading: 18 and 50 both fall in the middle group, so the cuts are
# AGE < 18, 18 <= AGE <= 50, AGE > 50. This matters on this study - the youngest
# subject is 50, so the boundary alone decides whether that subject is group 2
# or group 3.
# ------------------------------------------------------------------------------

adsl <- adsl %>%
  mutate(
    AGEGR9N = case_when(
      AGE < 18 ~ 1,
      AGE <= 50 ~ 2,
      AGE > 50 ~ 3
    ),
    AGEGR9 = case_when(
      AGEGR9N == 1 ~ "<18",
      AGEGR9N == 2 ~ "18 - 50",
      AGEGR9N == 3 ~ ">50"
    )
  )

# ------------------------------------------------------------------------------
# 3. TRTSDTM / TRTSTMF - datetime of first treatment
# ------------------------------------------------------------------------------

# One derive_vars_dtm() call yields both the imputed datetime (EXSTDTM) and the
# flag recording what was imputed (EXSTTMF). ignore_seconds_flag = TRUE is what
# implements the spec's "impute missing hours and minutes but not seconds": the
# flag reports hour/minute imputation and stays silent about seconds. It is also
# the package default, but it is passed explicitly so a reviewer can see the
# requirement was handled on purpose rather than inherited by accident.
ex_ext <- ex %>%
  derive_vars_dtm(
    dtc = EXSTDTC,
    new_vars_prefix = "EXST",
    ignore_seconds_flag = TRUE
  )

# The valid-dose filter (a real dose, or a zero dose that is placebo) comes from
# the {admiral} ADSL vignette; the assessment text says only "first exposure
# record". Checked against this extract: no subject's first exposure record is a
# zero-dose non-placebo, so the two readings give identical output here. The
# vignette filter is kept because it is the clinically correct definition of a
# treatment start.
adsl <- adsl %>%
  derive_vars_merged(
    dataset_add = ex_ext,
    filter_add = (EXDOSE > 0 | (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO"))) &
      !is.na(EXSTDTM),
    new_vars = exprs(TRTSDTM = EXSTDTM, TRTSTMF = EXSTTMF),
    order = exprs(EXSTDTM, EXSEQ),
    mode = "first",
    by_vars = exprs(STUDYID, USUBJID)
  )

# ------------------------------------------------------------------------------
# 4. ITTFL - intent-to-treat population flag
#
# Per the specification: "Y" where ARM is populated in DM, else "N". Taken
# literally, as written, rather than substituted with a stricter definition.
# ------------------------------------------------------------------------------

adsl <- adsl %>%
  mutate(ITTFL = if_else(!is.na(ARM) & ARM != "", "Y", "N"))

# ------------------------------------------------------------------------------
# 5. LSTAVLDT - last known alive date
#
# The subject is known to have been alive on the latest date on which any
# activity was documented for them, so the four source domains are pooled and
# the maximum taken. The spec says "any" record from each domain, so no domain
# filtering is applied beyond requiring a usable date.
#
# The condition tests the *converted* date rather than the raw --DTC string:
# 26 AE start dates in this extract are partial (year-month only), and
# convert_dtc_to_dt() returns NA for those. Testing the raw string would let
# those records pass the condition and then sort to the end as NA, which would
# hand back a missing LSTAVLDT for the subject.
#
# Each event picks one record per subject via order + mode, for determinism. The
# source domains hold many records that carry the same date - VS records roughly
# ten measurements per subject-visit, all sharing one VSDTC, and AE/DS/EX repeat
# dates the same way - so without a within-event selection admiral cannot order
# the tied records and warns about duplicates. The domain sequence number breaks
# the tie. This cannot move the result: the tied records all carry the same date,
# and LSTAVLDT is the maximum date, so which of them is picked is immaterial to
# the value. Verified against the previous run - LSTAVLDT is unchanged for all
# 306 subjects.
# ------------------------------------------------------------------------------

adsl <- adsl %>%
  derive_vars_extreme_event(
    by_vars = exprs(STUDYID, USUBJID),
    events = list(
      event(
        dataset_name = "vs",
        condition = !is.na(convert_dtc_to_dt(VSDTC)),
        set_values_to = exprs(LSTAVLDT = convert_dtc_to_dt(VSDTC)),
        order = exprs(convert_dtc_to_dt(VSDTC), VSSEQ),
        mode = "last"
      ),
      event(
        dataset_name = "ae",
        condition = !is.na(convert_dtc_to_dt(AESTDTC)),
        set_values_to = exprs(LSTAVLDT = convert_dtc_to_dt(AESTDTC)),
        order = exprs(convert_dtc_to_dt(AESTDTC), AESEQ),
        mode = "last"
      ),
      event(
        dataset_name = "ds",
        condition = !is.na(convert_dtc_to_dt(DSSTDTC)),
        set_values_to = exprs(LSTAVLDT = convert_dtc_to_dt(DSSTDTC)),
        order = exprs(convert_dtc_to_dt(DSSTDTC), DSSEQ),
        mode = "last"
      ),
      event(
        dataset_name = "ex",
        condition = !is.na(convert_dtc_to_dt(EXSTDTC)),
        set_values_to = exprs(LSTAVLDT = convert_dtc_to_dt(EXSTDTC)),
        order = exprs(convert_dtc_to_dt(EXSTDTC), EXSEQ),
        mode = "last"
      )
    ),
    source_datasets = list(vs = vs, ae = ae, ds = ds, ex = ex),
    tmp_event_nr_var = event_nr,
    order = exprs(LSTAVLDT, event_nr),
    mode = "last",
    new_vars = exprs(LSTAVLDT)
  )

# ------------------------------------------------------------------------------
# 6. Save
# ------------------------------------------------------------------------------

# TRTSDTM is a POSIXct. Formatting it explicitly on export keeps the time part
# visible in the CSV instead of leaving the representation to the writer.
adsl_out <- adsl %>%
  mutate(TRTSDTM = format(TRTSDTM, "%Y-%m-%dT%H:%M:%S"))

write.csv(adsl_out, "question_2_adam/adsl.csv", row.names = FALSE, na = "")

cat("ADSL built:", nrow(adsl), "rows,", ncol(adsl), "variables\n")
cat("Written to: question_2_adam/adsl.csv\n\n")
print(as.data.frame(utils::head(
  adsl[, c("USUBJID", "AGE", "AGEGR9", "AGEGR9N", "TRTSDTM", "TRTSTMF",
           "ITTFL", "LSTAVLDT")], 5
)))

# ------------------------------------------------------------------------------
# 7. Validation
#
# Only TRTSDTM and TRTSTMF exist in pharmaverseadam::adsl, so only those can be
# compared directly. AGEGR9/AGEGR9N/ITTFL have no counterpart there and are
# checked for internal consistency instead. LSTAVLDT has no counterpart either,
# but the reference carries LSTALVDT - a different spelling and a different
# definition - so that one is reported as an agreement rate, not as pass/fail.
# ------------------------------------------------------------------------------

cat("\n", strrep("-", 78), "\n", sep = "")
cat("VALIDATION\n")
cat(strrep("-", 78), "\n", sep = "")

adsl_chk <- as.data.frame(adsl)

# NA == NA must count as a match; a plain == would propagate NA.
differs <- function(a, b) {
  a <- unname(a)
  b <- unname(b)
  !((is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b))
}

# -- clean run ----------------------------------------------------------------
# The log is the evidence that this program runs error-free, so a silent warning
# buried in it should not pass unnoticed. admiral warns rather than errors when a
# derivation is ambiguous - duplicate records it cannot order, for instance - so
# a clean run means zero warnings, not merely zero errors.
run_warnings <- warnings()

cat("\n[0] Clean run\n")
cat("  Warnings raised:", length(run_warnings),
    if (length(run_warnings) == 0L) " OK\n" else " REVIEW THESE\n")
if (length(run_warnings) > 0L) print(run_warnings)

# -- structure ----------------------------------------------------------------
cat("\n[1] Structure\n")
cat("  Rows:", nrow(adsl_chk), "vs nrow(dm):", nrow(dm),
    if (nrow(adsl_chk) == nrow(dm)) " OK\n" else " MISMATCH\n")
cat("  Duplicate USUBJID:", sum(duplicated(adsl_chk$USUBJID)),
    if (anyDuplicated(adsl_chk$USUBJID) == 0) " OK\n" else " MISMATCH\n")

# -- TRTSDTM / TRTSTMF vs reference -------------------------------------------
cat("\n[2] TRTSDTM / TRTSTMF vs pharmaverseadam::adsl\n")

ref <- as.data.frame(pharmaverseadam::adsl)
cmp <- merge(
  adsl_chk[, c("USUBJID", "TRTSDTM", "TRTSTMF")],
  ref[, c("USUBJID", "TRTSDTM", "TRTSTMF")],
  by = "USUBJID", suffixes = c("_built", "_ref"), all.x = TRUE
)

for (v in c("TRTSDTM", "TRTSTMF")) {
  d <- differs(cmp[[paste0(v, "_built")]], cmp[[paste0(v, "_ref")]])
  cat(sprintf("  %-8s %s\n", v,
              if (sum(d) == 0L) "OK - 0 mismatches" else paste(sum(d), "mismatch(es)")))
  if (any(d)) {
    show <- utils::head(which(d), 5)
    print(data.frame(
      USUBJID = cmp$USUBJID[show],
      built = as.character(cmp[[paste0(v, "_built")]][show]),
      reference = as.character(cmp[[paste0(v, "_ref")]][show]),
      stringsAsFactors = FALSE
    ))
  }
}

# -- variables with no reference counterpart ----------------------------------
cat("\n[3] AGEGR9 / AGEGR9N (no reference counterpart - distribution + checks)\n")
print(table(adsl_chk$AGEGR9, adsl_chk$AGEGR9N, useNA = "ifany",
            dnn = c("AGEGR9", "AGEGR9N")))
cat("  AGEGR9N within 1:3       :",
    all(adsl_chk$AGEGR9N %in% 1:3), "\n")
cat("  AGEGR9 / AGEGR9N consistent:",
    all(mapply(function(lbl, num) {
      identical(lbl, c("<18", "18 - 50", ">50")[num])
    }, adsl_chk$AGEGR9, adsl_chk$AGEGR9N)), "\n")
cat("  Age range in data        :", paste(range(adsl_chk$AGE), collapse = " - "), "\n")

cat("\n[4] ITTFL (no reference counterpart - distribution + checks)\n")
print(table(adsl_chk$ITTFL, useNA = "ifany"))
cat("  Only \"Y\"/\"N\"             :",
    all(adsl_chk$ITTFL %in% c("Y", "N")), "\n")
cat("  ITTFL == \"Y\" count       :", sum(adsl_chk$ITTFL == "Y"), "\n")
cat("  Non-missing ARM count    :", sum(!is.na(dm$ARM) & dm$ARM != ""), "\n")
cat("  Counts agree             :",
    sum(adsl_chk$ITTFL == "Y") == sum(!is.na(dm$ARM) & dm$ARM != ""), "\n")

# -- LSTAVLDT vs the reference's differently-defined LSTALVDT ------------------
cat("\n[5] LSTAVLDT vs reference LSTALVDT (different variable - agreement only)\n")

lst <- merge(
  adsl_chk[, c("USUBJID", "LSTAVLDT")],
  ref[, c("USUBJID", "LSTALVDT")],
  by = "USUBJID", all.x = TRUE
)
agree <- !differs(lst$LSTAVLDT, lst$LSTALVDT)

cat("  Missing LSTAVLDT :", sum(is.na(lst$LSTAVLDT)), "\n")
cat("  Agreement        :", sum(agree), "/", nrow(lst),
    sprintf("(%.1f%%)", 100 * mean(agree)), "\n")
cat("  Differences are expected - the two variables are defined differently.\n")

if (any(!agree)) {
  show <- utils::head(which(!agree), 5)
  cat("  Examples:\n")
  print(data.frame(
    USUBJID = lst$USUBJID[show],
    LSTAVLDT_built = as.character(lst$LSTAVLDT[show]),
    LSTALVDT_ref = as.character(lst$LSTALVDT[show]),
    stringsAsFactors = FALSE
  ))
}

cat("\n", strrep("-", 78), "\n", sep = "")
sessionInfo()
