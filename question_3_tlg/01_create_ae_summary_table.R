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
#   - question_3_tlg/ae_summary_table.html (or .docx / .pdf)
#       Rows:    AETERM or AESOC (choice documented in README)
#       Columns: treatment groups (ACTARM) plus a total column of all subjects
#       Cells:   count (n) and percentage (%), sorted by descending frequency
#   - question_3_tlg/run_log_01.txt   console log proving an error-free run
#
# Author: Maksim Sendetski
# Date:   2026-09-02
# ------------------------------------------------------------------------------
