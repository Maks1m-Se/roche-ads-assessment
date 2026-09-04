# ------------------------------------------------------------------------------
# Title:   Question 2 - Create the ADaM Subject Level Analysis Dataset (ADSL)
#
# Purpose: Build ADSL from SDTM source data using the {admiral} family of
#          packages and tidyverse tools, with DM as the basis, and derive the
#          additional variables requested in the assessment specification.
#
# Input dataset(s):
#   - pharmaversesdtm::dm   basis of ADSL
#   - pharmaversesdtm::vs   vital signs (last known alive date)
#   - pharmaversesdtm::ex   exposure (treatment start date-time, last dose)
#   - pharmaversesdtm::ds   disposition (last known alive date)
#   - pharmaversesdtm::ae   adverse events (last known alive date)
#
# Output(s):
#   - ADSL dataset (format TBD) including the derived variables:
#       AGEGR9, AGEGR9N   age groups "<18" / "18 - 50" / ">50" (1 / 2 / 3)
#       TRTSDTM, TRTSTMF  first valid-dose exposure datetime + imputation flag
#       ITTFL             "Y"/"N" - ARM populated in DM
#       LSTAVLDT          last known alive date (VS / AE / DS / EX sources)
#   - question_2_adam/run_log.txt   console log proving an error-free run
#
# Author: Maksim Sendetski
# Date:   2026-09-02
# ------------------------------------------------------------------------------
