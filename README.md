# Roche ADS Programmer Coding Assessment

## 1. Overview

This repository contains my solutions to the Analytical Data Science (ADS) Programmer
Coding Assessment. The assessment covers the pharmaverse ecosystem end to end: building a
CDISC SDTM Disposition (DS) domain from raw eCRF data with `{sdtm.oak}` (Question 1),
deriving an ADaM Subject Level Analysis Dataset (ADSL) with `{admiral}` and tidyverse
tools (Question 2), producing regulatory-style adverse event tables and figures with
`{gtsummary}` and `{ggplot2}` (Question 3), and — as a bonus — a Python GenAI assistant
that translates free-text clinical questions into structured pandas queries over an
adverse event dataset (Question 4). Questions 1–3 are required and written in R;
Question 4 is the optional Python question. Every R question ships a plain-text run log
as evidence that the script executes without errors.

> **Status:** Question 1 is implemented and validated — the built DS domain matches
> `pharmaversesdtm::ds` on all 12 required variables with 0 mismatches. Questions 2 to 4
> are in progress; their scripts currently hold header documentation blocks only. Output
> artifacts and run logs appear as each question is completed.

## 2. Repository structure

```
roche-ads-assessment/
├── README.md                              this file
├── .gitignore                             R/OS ignores + assessment materials
├── question_1_sdtm/
│   ├── 01_create_ds_domain.R              builds the SDTM DS domain
│   ├── run_log.txt                        console log, proof of error-free run
│   └── ds.csv                             built DS domain, 0 mismatches vs reference
├── question_2_adam/
│   ├── create_adsl.R                      builds the ADaM ADSL dataset
│   ├── run_log.txt                        console log, proof of error-free run
│   └── <adsl dataset>                     resulting ADSL (format TBD)
├── question_3_tlg/
│   ├── 01_create_ae_summary_table.R       TEAE summary table via {gtsummary}
│   ├── 02_create_visualizations.R         two AE figures via {ggplot2}
│   ├── run_log_01.txt                     console log for the table script
│   ├── run_log_02.txt                     console log for the figures script
│   ├── ae_summary_table.html              table output (or .docx / .pdf)
│   └── *.png                              two AE plots
└── question_4_genai/                      Python GenAI assistant (bonus)
```

Folder and file names follow the assessment specification **verbatim**, including the
inconsistency that Questions 1 and 3 use numeric script prefixes while Question 2 does
not. This is intentional, not an oversight.

## 3. Questions

### Question 1 — SDTM DS domain creation using `{sdtm.oak}`

| | |
|---|---|
| **Objective** | Create a CDISC SDTMIG v3.4 compliant Disposition (DS) domain from raw clinical trial data. |
| **Input datasets** | `pharmaverseraw::ds_raw` (raw disposition records) and a `study_ct` controlled terminology object (codelist `C66727`; obtained from the pharmaverse GitHub link, from the pharmaverse SDTM examples, or built inline from the definition given in the assessment PDF). Supporting input: `pharmaversesdtm::dm`, for the `RFSTDTC` reference date that `DSSTDY` is counted from (see spec note 6 below). |
| **Output artifacts** | DS domain dataset containing `STUDYID`, `DOMAIN`, `USUBJID`, `DSSEQ`, `DSTERM`, `DSDECOD`, `DSCAT`, `VISITNUM`, `VISIT`, `DSDTC`, `DSSTDTC`, `DSSTDY`. |
| **How to run** | `Rscript question_1_sdtm/01_create_ds_domain.R > question_1_sdtm/run_log.txt 2>&1` |
| **Log evidence** | `question_1_sdtm/run_log.txt` |

### Question 2 — ADaM ADSL dataset creation

| | |
|---|---|
| **Objective** | Create an ADSL dataset from SDTM source data using the `{admiral}` family of packages and tidyverse tools, with `DM` as the basis. |
| **Input datasets** | `pharmaversesdtm::dm`, `pharmaversesdtm::vs`, `pharmaversesdtm::ex`, `pharmaversesdtm::ds`, `pharmaversesdtm::ae`. |
| **Output artifacts** | ADSL dataset with the four requested derivations: `AGEGR9`/`AGEGR9N`, `TRTSDTM`/`TRTSTMF`, `ITTFL`, `LSTAVLDT`. |
| **How to run** | `Rscript question_2_adam/create_adsl.R > question_2_adam/run_log.txt 2>&1` |
| **Log evidence** | `question_2_adam/run_log.txt` |

### Question 3 — TLG: adverse events reporting

| | |
|---|---|
| **Objective** | Produce a treatment-emergent adverse event (TEAE) summary table and two adverse event figures, in the style of the FDA TLG catalogue (Table 10). |
| **Input datasets** | `pharmaverseadam::adae` (TEAEs are records with `TRTEMFL == "Y"`) and `pharmaverseadam::adsl`. |
| **Output artifacts** | `ae_summary_table.html` (TEAE summary by `ACTARM` with a total column, n and %, descending frequency) and two PNG plots: AE severity by treatment, and the top 10 AEs with 95% CIs. |
| **How to run** | `Rscript question_3_tlg/01_create_ae_summary_table.R > question_3_tlg/run_log_01.txt 2>&1` and `Rscript question_3_tlg/02_create_visualizations.R > question_3_tlg/run_log_02.txt 2>&1` — one log per script, see the log convention below. |
| **Log evidence** | `question_3_tlg/run_log_01.txt` and `question_3_tlg/run_log_02.txt` |

### Question 4 — GenAI clinical data assistant (Python, bonus)

| | |
|---|---|
| **Objective** | Build a `ClinicalTrialDataAgent` that uses an LLM to map a free-text clinical question onto the correct adverse event column, without hard-coded keyword rules. |
| **Input datasets** | `adae.csv`, exported from `pharmaversesdtm::ae` (see spec note 1 below). |
| **Output artifacts** | An LLM call returning structured JSON (`target_column`, `filter_value`), an execution function applying the corresponding pandas filter and returning the count of unique `USUBJID` values plus the list of matching subject IDs, and a test script running three example queries. |
| **How to run** | To be documented when the solution is implemented. |
| **Log evidence** | Printed output of the test script (this question does not use the R log convention). |

## 4. Log convention

Each R script is run non-interactively, with its console output captured in that
question's folder:

```
Rscript <path/to/script.R> > <folder>/run_log.txt 2>&1
```

`2>&1` merges stderr into stdout, so the log records warnings and errors rather than only
the happy path. The logs are graded deliverables: they are tracked in git and explicitly
**not** ignored.

Question 3 has two scripts and so ships two logs (see spec note 10):

```
Rscript question_3_tlg/01_create_ae_summary_table.R > question_3_tlg/run_log_01.txt 2>&1
Rscript question_3_tlg/02_create_visualizations.R   > question_3_tlg/run_log_02.txt 2>&1
```

By convention every script in this repository closes with `sessionInfo()`, so each log
also records the R version, the platform and the exact package versions of that run.

## 5. Environment & reproducibility

- **R version:** the assessment requires R 4.2.0 or above; this repository was
  developed and run on R 4.6.1.
- **Platform used:** Windows 11 / PowerShell (the log convention above is verified there);
  the commands are identical on macOS and Linux.
- **Python version (Question 4):** 3.10 or above.

Required R packages:

```r
install.packages(c(
  "sdtm.oak",         # Q1  SDTM domain creation
  "pharmaverseraw",   # Q1  raw source data
  "admiral",          # Q2  ADaM derivations
  "pharmaversesdtm",  # Q2  SDTM source data
  "pharmaverseadam",  # Q3  ADaM source data
  "gtsummary",        # Q3  summary table
  "gt",               # Q3  table rendering
  "ggplot2",          # Q3  figures
  "dplyr",            # data manipulation
  "tidyr"             # data manipulation
))
```

This command was verified to install everything from CRAN as-is on 2026-09-02. The exact
versions used are recorded by `sessionInfo()` at the bottom of every log file.

## 6. Notes on spec decisions

Points where the specification is ambiguous, internally inconsistent, or needs a judgement
call. Each decision is recorded here so a reviewer can see the reasoning instead of having
to reverse-engineer it from the code.

| # | Question | Point | Decision / rationale |
|---|---|---|---|
| 1 | Q4 | The input file is named `adae.csv`, but the spec sources it from `pharmaversesdtm::ae` — an SDTM AE dataset, not an ADaM ADAE. | Follow the spec literally: export `pharmaversesdtm::ae` and save it under the file name `adae.csv`. The columns the agent must map to (`AESEV`, `AETERM`, `AESOC`) all exist in SDTM `ae`. |
| 2 | Q3 | Table rows: `AETERM` **or** `AESOC` — the spec permits either. | TBD — choice and rationale to be documented here once the table is built. |
| 3 | Q3 | AE incidence counting level | Count at subject level, not record level — a subject with five HEADACHE records is one subject with headache. Applies to the summary table and to Plot 2. |
| 4 | Q3 | Denominator for percentages | Subjects per treatment arm from `pharmaverseadam::adsl`, not subjects with AEs from `adae`. This is why the spec lists `adsl` as a Q3 input. |
| 5 | Q3 | Confidence interval method for Plot 2 | Clopper-Pearson, as stated in the sample output subtitle in the assessment PDF. Use an established function, do not hand-roll. |
| 6 | Q1 | `DSSTDY` needs a reference date | The spec lists only `ds_raw` as input, but study day cannot be computed without a subject reference start date, which lives in DM. Added `pharmaversesdtm::dm` as a supporting input and used `RFSTDTC` as the reference date via `derive_study_day()`. Recorded here because it is an input beyond the literal spec. |
| 7 | Q1 | `DSDECOD` controlled terminology vs reference behaviour | SDTMIG v3.4 defines `DSDECOD` through three codelists selected by `DSCAT` (NCOMPLT / PROTMLST / OTHEVENT). The assessment supplies only `C66727`, and the reference DS produces `DSDECOD` by upper-casing the collected value. Implemented `assign_ct()` with `C66727` on the dropdown branch to demonstrate CT tooling; free-text reasons are mapped verbatim. Net output matches the reference exactly. `"RANDOMIZED"` is a protocol milestone (PROTMLST family), which is why it is absent from `C66727`. |
| 8 | Q1 | `DSSEQ` sequencing rule | Subjects have multiple DS records sharing a visit and a date, so a deterministic order was needed. Reverse-engineered against the reference: it sequences purely by collection/entry order within subject (raw row order), not by visit number or date. Subject `01-705-1382` confirms it — its randomization milestone was entered after a later-visit event and the reference preserves that raw order rather than sorting by visit. Implemented as `rec_vars = c("USUBJID", <raw row order>)`. |
| 9 | Q1 | Unscheduled visit numbers | Six unscheduled visit labels are absent from the CT `VISITNUM` / `VISIT` codelists. Derived the number from the label itself, following the CT's own precedent `"Unscheduled 3.1" -> 3.1`. 8 records affected. |
| 10 | Q3 | Number of log files | The deliverables list is singular ("A text file/log file") for Questions 1 and 2, which have one script each, and plural ("Text files/log files") for Question 3, the only question with two scripts. Question 3 therefore ships one log per script, `run_log_01.txt` and `run_log_02.txt`; Questions 1 and 2 keep a single `run_log.txt`. |

*Extend this table as further decisions are made — one row per decision, newest at the
bottom.*

## 7. References

- Subject Disposition aCRF — mock-up eCRF with the General Notes for Question 1:
  https://github.com/pharmaverse/pharmaverseraw/blob/main/vignettes/articles/aCRFs/Subject_Disposition_aCRF.pdf
- CDISC SDTM Implementation Guide v3.4: https://www.cdisc.org/standards/foundational/sdtmig/sdtmig-v3-4
- Pharmaverse examples: https://pharmaverse.github.io/examples/
- `{sdtm.oak}` documentation: https://pharmaverse.github.io/sdtm.oak/
- `{admiral}` documentation: https://pharmaverse.github.io/admiral/
- `{gtsummary}` documentation: https://www.danieldsjoberg.com/gtsummary/
- FDA TLG catalogue: https://pharmaverse.github.io/cardinal/quarto/index-catalog.html
