# ------------------------------------------------------------------------------
# Title:   Question 1 - Create the SDTM Disposition (DS) domain using {sdtm.oak}
#
# Purpose: Map the raw disposition data collected on the Subject Disposition eCRF
#          into a CDISC SDTMIG v3.4 compliant DS domain dataset.
#
# Input dataset(s):
#   - pharmaverseraw::ds_raw          raw (collected) disposition records, 850 rows
#   - question_1_sdtm/sdtm_ct.csv     study controlled terminology, ships with the repo
#   - pharmaversesdtm::dm             reference start date (RFSTDTC) for DSSTDY
#
# Output(s):
#   - question_1_sdtm/ds.csv          DS domain, 850 rows, with these 12 variables
#                                     in this order:
#       STUDYID, DOMAIN, USUBJID, DSSEQ, DSTERM, DSDECOD, DSCAT,
#       VISITNUM, VISIT, DSDTC, DSSTDTC, DSSTDY
#     DSSPID is present in pharmaversesdtm::ds but is not required here, so it is
#     deliberately not derived.
#   - question_1_sdtm/run_log.txt     console log proving an error-free run
#
# Author: Maksim Sendetski
# Date:   2026-09-04
# ------------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(sdtm.oak)
  library(dplyr)
})

# ------------------------------------------------------------------------------
# 1. Source data
# ------------------------------------------------------------------------------

ds_raw <- as.data.frame(pharmaverseraw::ds_raw)
dm <- as.data.frame(pharmaversesdtm::dm)
study_ct <- read.csv("question_1_sdtm/sdtm_ct.csv", stringsAsFactors = FALSE)

# Stamp the collection order onto the raw data before any derivation runs, so it
# survives as a stable tiebreak for DSSEQ (see section 4).
ds_raw <- ds_raw %>%
  mutate(.raw_row = row_number())

cat("Raw records read:", nrow(ds_raw), "\n")
cat("Subjects in raw  :", length(unique(ds_raw$PATNUM)), "\n\n")

# {sdtm.oak} joins every mapping step back onto the raw data by an oak key rather
# than by row position, which is what makes conditional (row-subset) mappings
# composable. The key has to be stamped onto the raw data before any mapping.
ds_raw <- generate_oak_id_vars(
  raw_dat = ds_raw,
  pat_var = "PATNUM",
  raw_src = "ds_raw"
)

# ------------------------------------------------------------------------------
# 2. Raw-level preparation
#
# Everything below prepares *collected* values so the mapping steps in section 3
# stay declarative. No SDTM variable is created here.
# ------------------------------------------------------------------------------

# The eCRF captures a disposition reason in one of two mutually exclusive ways:
# a dropdown (IT.DSDECOD + IT.DSTERM) or, when the dropdown does not fit, a
# free-text "other, specify" field (OTHERSP). Verified on this extract: the two
# never co-occur, so a record belongs to exactly one branch.
ds_raw <- ds_raw %>%
  mutate(
    is_free_text = !is.na(OTHERSP),

    # SDTM character findings are submitted in upper case. The free-text answer
    # is both the verbatim reason and, absent any codeable dropdown value, the
    # standardised one - hence it feeds DSTERM and DSDECOD alike.
    DSTERM_DROPDOWN = toupper(.data[["IT.DSTERM"]]),
    DSTERM_FREETEXT = toupper(OTHERSP),
    DSDECOD_FREETEXT = toupper(OTHERSP)
  )

# The visit CT stores the CRF spelling in collected_value. INSTANCE is recorded
# with slightly different capitalisation ("Ambul Ecg Removal" vs the CT's
# "Ambul ECG Removal"), and assign_ct() matches case-sensitively, so the raw
# label is snapped to the CT's own spelling first. Matching case-insensitively
# rather than patching the one known string keeps this robust to further case
# drift in the source.
visit_collected <- unique(study_ct$collected_value[study_ct$codelist_code == "VISIT"])
ds_raw$INSTANCE_CT <- visit_collected[match(toupper(ds_raw$INSTANCE),
                                            toupper(visit_collected))]

# Six unscheduled visit labels are absent from the study CT entirely. The CT does
# contain "Unscheduled 3.1" -> VISIT "UNSCHEDULED 3.1" / VISITNUM 3.1, so the
# number embedded in the label *is* the visit number by study convention. The
# remaining unscheduled labels follow that same precedent rather than being
# dropped, which would leave timing variables blank on real disposition records.
is_unscheduled <- is.na(ds_raw$INSTANCE_CT)
ds_raw$VISIT_UNSCH <- ifelse(is_unscheduled, toupper(ds_raw$INSTANCE), NA_character_)
ds_raw$VISITNUM_UNSCH <- ifelse(is_unscheduled,
                                sub("^[^0-9]*", "", ds_raw$INSTANCE),
                                NA_character_)

cat("Visit labels resolved via CT      :", sum(!is_unscheduled), "\n")
cat("Visit labels derived from the label:", sum(is_unscheduled), "\n")
cat("  ", paste(sort(unique(ds_raw$INSTANCE[is_unscheduled])), collapse = ", "), "\n\n")

# ------------------------------------------------------------------------------
# 3. Map the raw fields onto DS variables
# ------------------------------------------------------------------------------

# DSTERM - the verbatim reason exactly as the site recorded it.
ds <-
  assign_no_ct(
    tgt_var = "DSTERM",
    raw_dat = condition_add(ds_raw, !is_free_text),
    raw_var = "DSTERM_DROPDOWN"
  ) %>%
  assign_no_ct(
    tgt_var = "DSTERM",
    raw_dat = condition_add(ds_raw, is_free_text),
    raw_var = "DSTERM_FREETEXT"
  ) %>%

  # DSDECOD - the standardised reason. The dropdown branch goes through the
  # C66727 (Completion/Reason for Non-Completion) codelist so the mapping is
  # driven by the CT file rather than by hand-written recoding. assign_ct() in
  # 0.2.0 matches collected_value/term_synonyms case-sensitively and upper-cases
  # anything it cannot match, which it reports on the console. That fallback is
  # safe here because every unmatched collected value ("Randomized", "Completed",
  # "Screen Failure", "Lost to Follow-Up", "Study Terminated by Sponsor") differs
  # from its CT term only in case or in a CT-side prefix, so the upper-cased
  # value is already the submission value. The console note is expected output,
  # not an error.
  assign_ct(
    tgt_var = "DSDECOD",
    raw_dat = condition_add(ds_raw, !is_free_text),
    raw_var = "IT.DSDECOD",
    ct_spec = study_ct,
    ct_clst = "C66727"
  ) %>%
  assign_no_ct(
    tgt_var = "DSDECOD",
    raw_dat = condition_add(ds_raw, is_free_text),
    raw_var = "DSDECOD_FREETEXT"
  ) %>%

  # DSCAT - randomisation is a protocol milestone, not a disposition event: it
  # records that the subject reached a planned point in the trial, whereas a
  # disposition event records how their participation in an epoch ended. Anything
  # captured as free text is by definition outside the disposition codelist and
  # is filed as an other event.
  hardcode_no_ct(
    tgt_val = "OTHER EVENT",
    raw_dat = condition_add(ds_raw, is_free_text),
    raw_var = "PATNUM",
    tgt_var = "DSCAT"
  ) %>%
  hardcode_no_ct(
    tgt_val = "PROTOCOL MILESTONE",
    raw_dat = condition_add(ds_raw, !is_free_text & `IT.DSDECOD` == "Randomized"),
    raw_var = "PATNUM",
    tgt_var = "DSCAT"
  ) %>%
  hardcode_no_ct(
    tgt_val = "DISPOSITION EVENT",
    raw_dat = condition_add(ds_raw, !is_free_text & `IT.DSDECOD` != "Randomized"),
    raw_var = "PATNUM",
    tgt_var = "DSCAT"
  ) %>%

  # VISIT / VISITNUM - scheduled visits come from the study CT; the unscheduled
  # ones from the label, per the precedent noted in section 2.
  assign_ct(
    tgt_var = "VISIT",
    raw_dat = condition_add(ds_raw, !is.na(INSTANCE_CT)),
    raw_var = "INSTANCE_CT",
    ct_spec = study_ct,
    ct_clst = "VISIT"
  ) %>%
  assign_no_ct(
    tgt_var = "VISIT",
    raw_dat = condition_add(ds_raw, is.na(INSTANCE_CT)),
    raw_var = "VISIT_UNSCH"
  ) %>%
  assign_ct(
    tgt_var = "VISITNUM",
    raw_dat = condition_add(ds_raw, !is.na(INSTANCE_CT)),
    raw_var = "INSTANCE_CT",
    ct_spec = study_ct,
    ct_clst = "VISITNUM"
  ) %>%
  assign_no_ct(
    tgt_var = "VISITNUM",
    raw_dat = condition_add(ds_raw, is.na(INSTANCE_CT)),
    raw_var = "VISITNUM_UNSCH"
  )

# ------------------------------------------------------------------------------
# 4. Identifiers, dates and timing
# ------------------------------------------------------------------------------

# Join on the oak key rather than assuming the mapped frame kept raw row order.
ds <- ds %>%
  left_join(
    ds_raw %>%
      mutate(
        STUDYID = STUDY,
        USUBJID = paste0("01-", PATNUM),
        RAW_DSSTDAT = .data[["IT.DSSTDAT"]],
        RAW_DSDTCOL = DSDTCOL,
        RAW_DSTMCOL = DSTMCOL
      ) %>%
      select(all_of(oak_id_vars()), STUDYID, USUBJID, .raw_row,
             RAW_DSSTDAT, RAW_DSDTCOL, RAW_DSTMCOL),
    by = oak_id_vars()
  ) %>%
  mutate(
    DOMAIN = "DS",

    # VISITNUM arrives as the CT term / parsed label, i.e. character. It has to
    # be numeric before DSSEQ is derived, otherwise records sort lexically and
    # visit 13 would precede visit 3.
    VISITNUM = as.numeric(VISITNUM),

    # The eCRF collects dates as MM-DD-YYYY; SDTM requires ISO 8601.
    DSSTDTC = create_iso8601(RAW_DSSTDAT, .format = "m-d-y"),

    # DSDTC is the collection date-time. Time is only captured on some forms, so
    # the result is a date-time where a time exists and a plain date otherwise -
    # create_iso8601() truncates to the collected precision rather than imputing.
    DSDTC = create_iso8601(RAW_DSDTCOL, RAW_DSTMCOL, .format = c("m-d-y", "H:M"))
  )

# DSSEQ must be unique within subject. The reference domain sequences DS records
# purely by the order they were collected and entered on the CRF - visit number
# and event date are not sort keys. Subject 01-705-1382 is the case that proves
# it: their Randomized/Baseline record was entered after a Week 2 disposition
# event, and the reference keeps that entry order rather than sorting Baseline
# back to the front. Raw row order within subject is therefore the whole sort,
# not a tiebreak. .raw_row is a processing aid only; it is dropped in section 5.
ds <- derive_seq(
  tgt_dat = ds,
  tgt_var = "DSSEQ",
  rec_vars = c("USUBJID", ".raw_row")
)

# DSSTDY is study day of the event, counted from the subject's first study
# treatment date in DM. Day 1 is the reference date itself; there is no day 0.
ds <- derive_study_day(
  sdtm_in = ds,
  dm_domain = dm,
  tgdt = "DSSTDTC",
  refdt = "RFSTDTC",
  study_day_var = "DSSTDY",
  merge_key = "USUBJID"
)

# ------------------------------------------------------------------------------
# 5. Final domain
# ------------------------------------------------------------------------------

ds_vars <- c(
  "STUDYID", "DOMAIN", "USUBJID", "DSSEQ", "DSTERM", "DSDECOD", "DSCAT",
  "VISITNUM", "VISIT", "DSDTC", "DSSTDTC", "DSSTDY"
)

ds_domain <- ds %>%
  select(all_of(ds_vars)) %>%
  arrange(USUBJID, DSSEQ)

write.csv(ds_domain, "question_1_sdtm/ds.csv", row.names = FALSE, na = "")

cat("DS domain built:", nrow(ds_domain), "rows,", ncol(ds_domain), "variables\n")
cat("Written to     : question_1_sdtm/ds.csv\n\n")
print(utils::head(as.data.frame(ds_domain), 5))

# ------------------------------------------------------------------------------
# 6. Validation against the reference DS domain
#
# pharmaversesdtm::ds is the same study built independently, so it serves as an
# expected-result check on all 12 required variables. DSSPID is in the reference
# but out of scope and is not compared.
# ------------------------------------------------------------------------------

cat("\n", strrep("-", 78), "\n", sep = "")
cat("VALIDATION vs pharmaversesdtm::ds\n")
cat(strrep("-", 78), "\n", sep = "")

ds_ref <- as.data.frame(pharmaversesdtm::ds) %>%
  select(all_of(ds_vars)) %>%
  arrange(USUBJID, DSSEQ)

ds_built <- as.data.frame(ds_domain)

cat("Rows built / reference:", nrow(ds_built), "/", nrow(ds_ref), "\n\n")

if (!identical(nrow(ds_built), nrow(ds_ref))) {
  cat("Row counts differ - per-variable comparison skipped.\n")
} else {
  # NA == NA has to count as a match; a plain == would propagate NA.
  differs <- function(a, b) {
    a <- unname(a)
    b <- unname(b)
    !((is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b))
  }

  total_mismatches <- 0L

  for (v in ds_vars) {
    d <- differs(ds_built[[v]], ds_ref[[v]])
    n <- sum(d)
    total_mismatches <- total_mismatches + n
    cat(sprintf("%-9s %s\n", v,
                if (n == 0L) "OK" else paste(n, "mismatch(es)")))

    if (n > 0L) {
      show <- utils::head(which(d), 5)
      print(data.frame(
        row = show,
        USUBJID = ds_ref$USUBJID[show],
        DSSEQ = ds_ref$DSSEQ[show],
        built = as.character(ds_built[[v]][show]),
        reference = as.character(ds_ref[[v]][show]),
        stringsAsFactors = FALSE
      ))
    }
  }

  cat("\nTotal mismatches across all 12 variables:", total_mismatches, "\n")
}

cat("\n", strrep("-", 78), "\n", sep = "")
sessionInfo()
