# ------------------------------------------------------------------------------
# Title:   Question 3 (Table) - Treatment-emergent adverse event summary table
#
# Purpose: Produce a regulatory-style TEAE summary table with {gtsummary},
#          modelled on FDA TLG Catalogue Table 10.
#
# Input dataset(s):
#   - pharmaverseadam::adae   adverse events (TEAEs are TRTEMFL == "Y")
#   - pharmaverseadam::adsl   subject level data (denominators, ACTARM)
#
# Output(s):
#   - question_3_tlg/ae_summary_table.html
#       Rows:    AESOC with AETERM nested underneath
#       Columns: treatment groups (ACTARM) plus a total column of all subjects
#       Cells:   subject count (n) and percentage (%), descending frequency
#   - question_3_tlg/run_log_01.txt   console log proving an error-free run
#
# Author: Maksim Sendetski
# Date:   2026-09-02
# ------------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(gtsummary)
  library(gt)
  library(pharmaverseadam)
})

# ------------------------------------------------------------------------------
# 1. Source data
# ------------------------------------------------------------------------------

adae <- pharmaverseadam::adae
adsl <- pharmaverseadam::adsl

# ------------------------------------------------------------------------------
# 2. Analysis population (the denominator)
# ------------------------------------------------------------------------------

# The percentages in an AE table are incidence rates: of everyone who could have
# reported the event, what share did. The denominator therefore has to come from
# the subject-level dataset, never from ADAE - a subject who was treated and had
# no adverse event exists in ADSL and simply never appears in ADAE, so counting
# ADAE subjects would silently drop them and inflate every percentage.
#
# ADSL also carries a fourth ACTARM, "Screen Failure": 52 subjects who were
# screened but never randomised or dosed. They were never at risk of a
# treatment-emergent event and are absent from ADAE entirely, so including them
# would inflate the denominator (306 instead of 254) and deflate every rate.
# The analysis population is the three actual treatment arms: 86 + 72 + 96 = 254.

TRT_ARMS <- c("Placebo", "Xanomeline Low Dose", "Xanomeline High Dose")

pop <- adsl %>%
  filter(ACTARM %in% TRT_ARMS)

# ------------------------------------------------------------------------------
# 3. Treatment-emergent adverse events (the numerator)
# ------------------------------------------------------------------------------

# TRTEMFL flags events that started on or after first dose - i.e. events that
# could plausibly be attributed to treatment. Events predating the first dose
# are excluded from a TEAE table by definition.

teae <- adae %>%
  filter(TRTEMFL == "Y")

# ------------------------------------------------------------------------------
# 4. TEAE summary table
# ------------------------------------------------------------------------------

# Counting is at SUBJECT level, not record level. A subject who reports headache
# on five separate occasions contributes five ADAE records but is one subject
# with headache; the table reports subjects affected, so five records must
# collapse to one. tbl_hierarchical()'s id argument enforces exactly this - it
# counts distinct USUBJID within each cell rather than rows.
#
# variables = c(AESOC, AETERM) gives the FDA Table 10 layout: system organ class
# as the outer level, with the reported preferred terms nested underneath it.
# Note that a subject counted once under a nested term may still be counted once
# under the SOC for a different term, so SOC rows are not the sum of their terms
# - that is correct behaviour for an incidence table, not an inconsistency.
#
# overall_row = TRUE adds the "any adverse event" row that regulatory AE tables
# conventionally lead with.

tbl <- tbl_hierarchical(
  data        = teae,
  variables   = c(AESOC, AETERM),
  id          = USUBJID,
  denominator = pop,
  by          = ACTARM,
  statistic   = everything() ~ "{n} ({p}%)",
  overall_row = TRUE
)

# add_overall() must be applied BEFORE sort_hierarchical(): verified against
# gtsummary 2.6.0, calling it on an already-sorted hierarchical table errors with
# "the overall statistic cannot be added". Sorting afterwards is not a
# compromise - the row order is byte-identical either way, because the total
# column contributes no new ranking information over the sum of the arms.
# last = TRUE places the total column on the right, following the FDA layout.
#
# sort_hierarchical() sorts descending by count sums, applied within each level
# of the hierarchy: system organ classes are ordered by total frequency, and the
# terms within each class are ordered by frequency among themselves.

tbl <- tbl %>%
  add_overall(last = TRUE) %>%
  sort_hierarchical() %>%
  modify_caption(
    "**Table 10. Summary of Treatment-Emergent Adverse Events by System Organ Class and Preferred Term**"
  ) %>%
  modify_source_note(
    paste(
      "Treatment-emergent adverse events (TRTEMFL = 'Y').",
      "Counts are subjects with at least one event, not event records.",
      "Percentages use the number of treated subjects in each arm as denominator."
    )
  )

# ------------------------------------------------------------------------------
# 5. Export
# ------------------------------------------------------------------------------

out_html <- file.path("question_3_tlg", "ae_summary_table.html")

tbl %>%
  as_gt() %>%
  gtsave(filename = out_html)

# ------------------------------------------------------------------------------
# 6. Validation
# ------------------------------------------------------------------------------

cat("\n================ VALIDATION ================\n")

cat("\n[1] TEAE record count\n")
cat("  Rows in adae:            ", nrow(adae), "\n")
cat("  Rows with TRTEMFL == 'Y':", nrow(teae),
    if (nrow(teae) == 1122L) " OK (expected 1122)\n" else " MISMATCH (expected 1122)\n")

cat("\n[2] Denominator\n")
pop_n <- pop %>% count(ACTARM, name = "N")
print(as.data.frame(pop_n))
cat("  Total N:", nrow(pop),
    if (nrow(pop) == 254L) " OK (expected 254)\n" else " MISMATCH (expected 254)\n")
cat("  Screen Failure excluded:",
    if (!"Screen Failure" %in% pop$ACTARM) "OK\n" else "FAILED - still present\n")
cat("  adsl arms in table vs adae arms identical:",
    if (identical(sort(unique(pop$ACTARM)), sort(unique(teae$ACTARM)))) "OK\n" else "MISMATCH\n")

# Spot-check that counting really is subject-level. This term is chosen because
# its record count and its subject count differ: if the table were counting rows
# it would print the larger number.
cat("\n[3] Subject-level counting spot check\n")
spot_term <- "APPLICATION SITE PRURITUS"
spot_arm  <- "Xanomeline High Dose"

spot_rows <- teae %>% filter(AETERM == spot_term, ACTARM == spot_arm)
spot_subj <- n_distinct(spot_rows$USUBJID)
spot_deno <- sum(pop$ACTARM == spot_arm)

# Locate the statistic column belonging to that arm from the rendered header,
# rather than assuming a fixed stat_n position.
hdr <- tbl$table_styling$header
spot_col <- hdr$column[grepl(spot_arm, hdr$label, fixed = TRUE)][1]
spot_cell <- tbl$table_body %>%
  filter(variable == "AETERM", label == spot_term) %>%
  pull(all_of(spot_col))

cat("  Term / arm:      ", spot_term, "/", spot_arm, "\n")
cat("  ADAE records:    ", nrow(spot_rows), "\n")
cat("  Distinct subjects:", spot_subj, "of", spot_deno,
    paste0("(", round(100 * spot_subj / spot_deno, 1), "%)"), "\n")
cat("  Table cell:      ", spot_cell, "\n")
cat("  Subject-level:   ",
    if (grepl(paste0("^", spot_subj, " "), spot_cell)) "OK - matches subjects, not records\n"
    else " MISMATCH\n")

cat("\n[4] Output file\n")
cat("  Path:   ", out_html, "\n")
cat("  Written:", file.exists(out_html),
    if (file.exists(out_html)) paste0(" (", file.size(out_html), " bytes)\n") else "\n")

cat("\n[5] Table dimensions\n")
cat("  Rows in table body:", nrow(tbl$table_body), "\n")
cat("  System organ classes:", n_distinct(teae$AESOC), "\n")
cat("  Preferred terms:     ", n_distinct(teae$AETERM), "\n")

cat("\n============== END VALIDATION ==============\n\n")

sessionInfo()
