# ------------------------------------------------------------------------------
# Title:   Question 1 - Create the SDTM Disposition (DS) domain using {sdtm.oak}
#
# Purpose: Map the raw disposition data collected on the Subject Disposition eCRF
#          into a CDISC SDTMIG v3.4 compliant DS domain dataset.
#
# Input dataset(s):
#   - pharmaverseraw::ds_raw   raw (collected) disposition records
#   - study_ct                 study controlled terminology object
#                              (codelist C66727; sourced per the assessment PDF)
#
# Output(s):
#   - DS domain dataset (format TBD) containing, in this order:
#       STUDYID, DOMAIN, USUBJID, DSSEQ, DSTERM, DSDECOD, DSCAT,
#       VISITNUM, VISIT, DSDTC, DSSTDTC, DSSTDY
#   - question_1_sdtm/run_log.txt   console log proving an error-free run
#
# Author: Maksim Sendetski
# Date:   2026-09-02
#
# NOTE: implementation to be written by hand
# ------------------------------------------------------------------------------
