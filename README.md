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

> **Status:** this repository is currently scaffolded. The R scripts contain header
> documentation blocks only; the derivation logic and the Python solution are being
> written incrementally. Output artifacts and run logs appear as each question is
> completed.

## 2. Repository structure

```
roche-ads-assessment/
├── README.md                              this file
├── .gitignore                             R/OS ignores + assessment materials
├── question_1_sdtm/
│   ├── 01_create_ds_domain.R              builds the SDTM DS domain
│   ├── run_log.txt                        console log, proof of error-free run
│   └── <ds dataset>                       resulting DS domain (format TBD)
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
| **Input datasets** | `pharmaverseraw::ds_raw` (raw disposition records) and a `study_ct` controlled terminology object (codelist `C66727`; obtained from the pharmaverse GitHub link, from the pharmaverse SDTM examples, or built inline from the definition given in the assessment PDF). |
| **Output artifacts** | DS domain dataset containing `STUDYID`, `DOMAIN`, `USUBJID`, `DSSEQ`, `DSTERM`, `DSDECOD`, `DSCAT`, `VISITNUM`, `VISIT`, `DSDTC`, `DSSTDTC`, `DSSTDY`. |
| **How to run** | `Rscript question_1_sdtm/01_create_ds_domain.R > question_1_sdtm/run_log.txt 2>&1` |
| **Log evidence** | `question_1_sdtm/run_log.txt` |

### Question 2 — ADaM ADSL dataset creation

| | |
|---|---|
| **Objective** | Create an ADSL dataset from SDTM source data using the `{admiral}` family of packages and tidyverse tools, with `DM` as the basis. |
| **Input datasets** | `pharmaversesdtm::dm`, `pharmaversesdtm::vs`, `pharmaversesdtm::ex`, `pharmaversesdtm::ds`, `pharmaversesdtm::ae`. |
| **Output artifacts** | ADSL dataset including the requested derivations: `AGEGR9` / `AGEGR9N` (age groups `"<18"`, `"18 - 50"`, `">50"` numbered 1/2/3), `TRTSDTM` / `TRTSTMF` (first valid-dose exposure datetime with hour and minute imputation, and the corresponding imputation flag), `ITTFL` (`"Y"` where `DM.ARM` is populated, else `"N"`), and `LSTAVLDT` (last known alive date across vital signs, adverse event onset, disposition and exposure). |
| **How to run** | `Rscript question_2_adam/create_adsl.R > question_2_adam/run_log.txt 2>&1` |
| **Log evidence** | `question_2_adam/run_log.txt` |

### Question 3 — TLG: adverse events reporting

| | |
|---|---|
| **Objective** | Produce a treatment-emergent adverse event (TEAE) summary table and two adverse event figures, in the style of the FDA TLG catalogue (Table 10). |
| **Input datasets** | `pharmaverseadam::adae` (TEAEs are records with `TRTEMFL == "Y"`) and `pharmaverseadam::adsl`. |
| **Output artifacts** | `ae_summary_table.html` (or `.docx` / `.pdf`) — rows by `AETERM` or `AESOC`, columns by treatment group (`ACTARM`) plus a total column of all subjects, cells as count (n) and percentage (%), sorted by descending frequency. Two PNG plots: AE severity (`AESEV`) distribution by treatment, and the top 10 most frequent AEs (`AETERM`) with 95% confidence intervals for the incidence rates. |
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

## Log convention

Each R script is executed non-interactively and its complete console output — messages,
warnings and errors alike — is redirected into a `run_log.txt` inside that question's
folder:

```
Rscript <path/to/script.R> > <folder>/run_log.txt 2>&1
```

`2>&1` merges stderr into stdout, so the log is a faithful record of the whole run rather
than only its happy path. These logs are deliverables — the assessment asks for "a text
file/log file as evidence for code running error-free" — so they are tracked in git and
explicitly **not** ignored.

**Question 3 is the exception: one log per script, not one per folder.** The deliverables
list is written in the singular ("A text file/log file") for Questions 1 and 2, both of
which have a single script, but in the plural ("Text files/log files") for Question 3,
which is the only question with two scripts. Question 3 therefore produces two logs, each
one the untouched output of a single run:

```
Rscript question_3_tlg/01_create_ae_summary_table.R > question_3_tlg/run_log_01.txt 2>&1
Rscript question_3_tlg/02_create_visualizations.R   > question_3_tlg/run_log_02.txt 2>&1
```

Questions 1 and 2 keep their single `run_log.txt`.

Recommendation: end each R script with a call to `sessionInfo()`. The log then also
captures the R version, the platform and the exact versions of every attached package,
which lets a reviewer who was not at the keyboard reproduce and audit the run.

## 4. Environment & reproducibility

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

This command was verified to install everything from CRAN as-is on 2026-09-02, with the
versions: `sdtm.oak` 0.2.0, `pharmaverseraw` 0.1.1, `admiral` 1.5.0, `pharmaversesdtm`
1.5.0, `pharmaverseadam` 1.3.0, `gtsummary` 2.6.0, `gt` 1.3.0, `ggplot2` 4.0.3, `dplyr`
1.2.1, `tidyr` 1.3.2.

The package versions actually used for each run are also recorded by `sessionInfo()` at
the bottom of every log file.

## 5. Notes on spec decisions

Points where the specification is ambiguous, internally inconsistent, or needs a judgement
call. Each decision is recorded here so a reviewer can see the reasoning instead of having
to reverse-engineer it from the code.

| # | Question | Point | Decision / rationale |
|---|---|---|---|
| 1 | Q4 | The input file is named `adae.csv`, but the spec sources it from `pharmaversesdtm::ae` — an SDTM AE dataset, not an ADaM ADAE. | Follow the spec literally: export `pharmaversesdtm::ae` and save it under the file name `adae.csv`. The columns the agent must map to (`AESEV`, `AETERM`, `AESOC`) all exist in SDTM `ae`. |
| 2 | Q3 | Table rows: `AETERM` **or** `AESOC` — the spec permits either. | TBD — choice and rationale to be documented here once the table is built. |
| 3 | Q1 | `DSSTDY` reference start date. | TBD |

*Extend this table as further decisions are made — one row per decision, newest at the
bottom.*

## 6. References

- Subject Disposition aCRF — mock-up eCRF with the General Notes for Question 1:
  https://github.com/pharmaverse/pharmaverseraw/blob/main/vignettes/articles/aCRFs/Subject_Disposition_aCRF.pdf
- CDISC SDTM Implementation Guide v3.4: https://www.cdisc.org/standards/foundational/sdtmig/sdtmig-v3-4
- Pharmaverse examples: https://pharmaverse.github.io/examples/
- `{sdtm.oak}` documentation: https://pharmaverse.github.io/sdtm.oak/
- `{admiral}` documentation: https://pharmaverse.github.io/admiral/
- `{gtsummary}` documentation: https://www.danieldsjoberg.com/gtsummary/
- FDA TLG catalogue: https://pharmaverse.github.io/cardinal/quarto/index-catalog.html
