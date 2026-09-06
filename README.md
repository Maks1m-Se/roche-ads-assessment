# Roche ADS Programmer Coding Assessment

* [1. Overview](#1-overview)
* [2. Repository structure](#2-repository-structure)
* [3. Reproducing everything](#3-reproducing-everything)
* [4. Questions](#4-questions)
* [5. Log convention](#5-log-convention)
* [6. Environment & reproducibility](#6-environment--reproducibility)
* [7. Notes on spec decisions](#7-notes-on-spec-decisions)
* [8. References](#8-references)
* [9. Ideas for a production version](#9-ideas-for-a-production-version)

## 1. Overview

```
raw eCRF  ->  SDTM (Q1)  ->  ADaM (Q2)  ->  TLG (Q3)
                  |
                  +->  GenAI agent (Q4)
```

The four questions walk one clinical data flow rather than sitting apart: each stage
consumes the previous one, and the bonus agent branches off the SDTM layer because the
spec sources its input from `pharmaversesdtm::ae` (see spec note 1).

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

> **Status:** All four questions are complete — the three required ones and the optional
> Python bonus. The built DS domain matches `pharmaversesdtm::ds` on all 12 required
> variables with 0 mismatches, ADSL carries the four requested derivations, Question 3
> ships the TEAE summary table and both figures, and the Question 4 agent has been run
> against a real LLM. Every script runs without errors or warnings, and its log is
> committed as evidence.

## 2. Repository structure

```
roche-ads-assessment/
├── README.md                              this file
├── .gitignore                             R/OS/Python ignores + assessment materials
├── .gitattributes                         line-ending normalisation for future commits
├── question_1_sdtm/
│   ├── 01_create_ds_domain.R              builds the SDTM DS domain
│   ├── sdtm_ct.csv                        CT input: codelists for DSDECOD (C66727),
│   │                                      VISIT and VISITNUM
│   ├── run_log.txt                        console log, proof of error-free run
│   └── ds.csv                             built DS domain, 0 mismatches vs reference
├── question_2_adam/
│   ├── create_adsl.R                      builds the ADaM ADSL dataset
│   ├── run_log.txt                        console log, proof of error-free run
│   └── adsl.csv                           resulting ADSL with the four derivations
├── question_3_tlg/
│   ├── 01_create_ae_summary_table.R       TEAE summary table via {gtsummary}
│   ├── ae_summary_table.html              TEAE table, SOC rows with nested terms
│   ├── run_log_01.txt                     console log for the table script
│   ├── 02_create_visualizations.R         two AE figures via {ggplot2}
│   ├── run_log_02.txt                     console log for the figures script
│   ├── ae_severity_by_treatment.png       AE severity distribution by treatment arm
│   └── ae_top10_incidence_ci.png          top 10 AEs with 95% Clopper-Pearson CIs
└── question_4_genai/
    ├── clinical_agent.py                  ClinicalTrialDataAgent: parse, gate, execute
    ├── test_agent.py                      three example queries, one per column
    ├── adae.csv                           AE data exported from pharmaversesdtm::ae
    ├── requirements.txt                   pinned Python dependencies
    ├── .env.example                       key template; the real .env is gitignored
    └── run_log.txt                        console transcript of a real LLM run
```

Folder and file names follow the assessment specification **verbatim**, including the
inconsistency that Questions 1 and 3 use numeric script prefixes while Question 2 does
not. This is intentional, not an oversight.

## 3. Reproducing everything

Install the R and Python dependencies first — see
[section 6](#6-environment--reproducibility). Then, from the repository root, in this
order:

```bash
Rscript question_1_sdtm/01_create_ds_domain.R        > question_1_sdtm/run_log.txt   2>&1
Rscript question_2_adam/create_adsl.R                > question_2_adam/run_log.txt   2>&1
Rscript question_3_tlg/01_create_ae_summary_table.R  > question_3_tlg/run_log_01.txt 2>&1
Rscript question_3_tlg/02_create_visualizations.R    > question_3_tlg/run_log_02.txt 2>&1
python  question_4_genai/test_agent.py               > question_4_genai/run_log.txt  2>&1
```

Each command writes its own log. Question 4 needs `question_4_genai/.env`, which is not in
the repository: copy `question_4_genai/.env.example` to it and add your `OPENAI_API_KEY`.
Without that key the agent falls back to an offline mock parser.

Every log committed to this repository is the output of exactly these commands.

## 4. Questions

### Question 1 — SDTM DS domain creation using `{sdtm.oak}`

| | |
|---|---|
| **Objective** | Create a CDISC SDTMIG v3.4 compliant Disposition (DS) domain from raw clinical trial data. |
| **Input datasets** | `pharmaverseraw::ds_raw` (raw disposition records) and `question_1_sdtm/sdtm_ct.csv`, the controlled terminology committed with the repository — the script reads it into `study_ct` and uses the `C66727`, `VISIT` and `VISITNUM` codelists from it. Supporting input: `pharmaversesdtm::dm`, for the `RFSTDTC` reference date that `DSSTDY` is counted from (see spec note 6 below). |
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
| **Input datasets** | `question_4_genai/adae.csv`, exported from `pharmaversesdtm::ae` (see spec note 1 below) with `write.csv(pharmaversesdtm::ae, "question_4_genai/adae.csv", row.names = FALSE)`. 1,191 records, 225 subjects. |
| **Output artifacts** | `clinical_agent.py` (agent and query logic), `test_agent.py` (three example queries), `requirements.txt`, `.env.example`. |
| **How to run** | `pip install -r question_4_genai/requirements.txt`, copy `.env.example` to `.env` and add your key, then `python question_4_genai/test_agent.py`. |
| **Log evidence** | `question_4_genai/run_log.txt` — printed output of the test script (this question does not use the R log convention). |

**Architecture.** Exactly one non-deterministic step, and it is tightly fenced:

```
NL question → LLM parse (LangChain with_structured_output)
            → QuerySpec (Pydantic, validated)
            → allowlist gate (column must be queryable and present)
            → deterministic pandas filter
            → unique-subject count + sorted subject IDs
```

The LLM chooses only *which column* and *which value*. It never writes code, never
sees the dataframe and never touches the result. Everything downstream is ordinary
pandas — there is no `eval()`, no query string assembled from model output, and no
model-generated code executed anywhere. The allowlist gate is the safety boundary:
a column must appear both in the agent's catalogue (`AESEV`, `AETERM`, `AESOC`) and
in the loaded dataframe before it is ever used to index it.

**Interface.** The agent is exercised through `test_agent.py`, which runs three fixed
example queries — one per mappable column — and prints each question, its parsed
`QuerySpec`, the parse source, the subject count and the matching IDs. There is no
interactive prompt or REPL: the assessment asks for a block of code running three example
queries, so the entry point is a script rather than a session.

**Running without a key.** With no `OPENAI_API_KEY` the agent prints
`[LLM] No OPENAI_API_KEY found - using mock responses.` and parses with a small
deterministic rule table, so the pipeline is demonstrable offline. Every result is
tagged `source="openai"` or `source="mock"`, so a transcript is never ambiguous
about which parser produced it. The mock triggers **only** on a missing key — if a
key is present and the call fails, the error surfaces rather than silently
degrading to keyword matching.

## 5. Log convention

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

## 6. Environment & reproducibility

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

Required Python packages (Question 4):

```bash
pip install -r question_4_genai/requirements.txt
```

The versions are pinned in that file to the ones the agent was written and verified
against.

## 7. Notes on spec decisions

Points where the specification is ambiguous, internally inconsistent, or needs a judgement
call. Each decision is recorded here so a reviewer can see the reasoning instead of having
to reverse-engineer it from the code.

| # | Question | Point | Decision / rationale |
|---|---|---|---|
| 1 | Q4 | The input file is named `adae.csv`, but the spec sources it from `pharmaversesdtm::ae` — an SDTM AE dataset, not an ADaM ADAE. | **Export SDTM `ae`, keep the file name `adae.csv`.** Follow the spec literally: export `pharmaversesdtm::ae` and save it under the file name `adae.csv`. The columns the agent must map to (`AESEV`, `AETERM`, `AESOC`) all exist in SDTM `ae`. |
| 2 | Q3 | Table rows: `AETERM` **or** `AESOC` — the spec permits either. | **Both, nested: `AESOC` rows with `AETERM` beneath them.** Used both, nested — `AESOC` as grouping rows with `AETERM` preferred terms underneath, matching the FDA Table 10 layout in the sample output. The 230 distinct `AETERM` values in the TEAE subset would be an unreadable flat table on their own; the 23 system organ classes give it structure. `tbl_hierarchical()` supports the nesting natively. |
| 3 | Q3 | AE incidence counting level | **Subject level, not record level.** Count at subject level, not record level — a subject with five HEADACHE records is one subject with headache. Applies to the summary table and to Plot 2. |
| 4 | Q3 | Denominator for percentages in the **summary table** | **Subjects per arm from `adsl`, not from `adae`.** Subjects per treatment arm from `pharmaverseadam::adsl`, not subjects with AEs from `adae`. This is why the spec lists `adsl` as a Q3 input. The figures depart from this and follow the supplied sample output instead — see notes 12 and 13. |
| 5 | Q3 | Confidence interval method for Plot 2 | **Clopper-Pearson, via an established function.** Clopper-Pearson, as stated in the sample output subtitle in the assessment PDF. Use an established function, do not hand-roll. |
| 6 | Q1 | `DSSTDY` needs a reference date | **Added `dm` as a supporting input; `RFSTDTC` is the reference date.** The spec lists only `ds_raw` as input, but study day cannot be computed without a subject reference start date, which lives in DM. Added `pharmaversesdtm::dm` as a supporting input and used `RFSTDTC` as the reference date via `derive_study_day()`. Recorded here because it is an input beyond the literal spec. |
| 7 | Q1 | `DSDECOD` controlled terminology vs reference behaviour | **`assign_ct()` with `C66727`; net output matches the reference exactly.** SDTMIG v3.4 defines `DSDECOD` through three codelists selected by `DSCAT` (NCOMPLT / PROTMLST / OTHEVENT). The assessment supplies only `C66727`, and the reference DS produces `DSDECOD` by upper-casing the collected value. Implemented `assign_ct()` with `C66727` on the dropdown branch to demonstrate CT tooling; free-text reasons are mapped verbatim. Net output matches the reference exactly. `"RANDOMIZED"` is a protocol milestone (PROTMLST family), which is why it is absent from `C66727`. |
| 8 | Q1 | `DSSEQ` sequencing rule | **Raw collection order within subject - not visit, not date.** Subjects have multiple DS records sharing a visit and a date, so a deterministic order was needed. Reverse-engineered against the reference: it sequences purely by collection/entry order within subject (raw row order), not by visit number or date. Subject `01-705-1382` confirms it — its randomization milestone was entered after a later-visit event and the reference preserves that raw order rather than sorting by visit. Implemented as `rec_vars = c("USUBJID", <raw row order>)`. |
| 9 | Q1 | Unscheduled visit numbers | **Derived from the visit label itself.** Six unscheduled visit labels are absent from the CT `VISITNUM` / `VISIT` codelists. Derived the number from the label itself, following the CT's own precedent `"Unscheduled 3.1" -> 3.1`. 8 records affected. |
| 10 | Q3 | Number of log files | **Question 3 ships two logs; Questions 1 and 2 one each.** The deliverables list is singular ("A text file/log file") for Questions 1 and 2, which have one script each, and plural ("Text files/log files") for Question 3, the only question with two scripts. Question 3 therefore ships one log per script, `run_log_01.txt` and `run_log_02.txt`; Questions 1 and 2 keep a single `run_log.txt`. |
| 11 | Q3 | The **summary table's** denominator excludes the Screen Failure arm | **The summary table divides by the Safety population, N = 254.** `adsl` has four `ACTARM` values including `"Screen Failure"` (52 subjects who were screened but never treated); `adae` has only three. Screen failures cannot have a treatment-emergent adverse event, so the table's denominator is the three treatment arms, N = 254, not all 306 subjects. Percentages divide by the treated subjects in each arm (86 / 72 / 96). Including the untreated subjects would deflate every incidence rate. This note governs the table only — the two figures follow the supplied sample output and use a different population, recorded in notes 12 and 13. |
| 12 | Q3 | The figures and the table analyse different populations | **The figures use all ADAE records; the table uses `TRTEMFL == "Y"`. The asymmetry comes from the specification.** The table task states the treatment-emergent restriction explicitly; neither plot task mentions `TRTEMFL`, and the supplied sample output for Plot 2 is labelled "n = 225 subjects". ADAE holds exactly 225 unique `USUBJID` against 217 in its treatment-emergent subset, so the sample describes the unfiltered dataset. Each output follows the instruction it was given rather than being forced into an artificial consistency the spec does not ask for. Within the figures, Plot 1 additionally counts at event level rather than subject level: a subject with four mild events and one severe event contributes five events at five severities, and collapsing to subject level would discard exactly what a severity profile shows. That is a deliberate departure from note 3, which governs the incidence outputs; Plot 1's subtitle says "event records (not subjects)" so the distinction is never left to inference. |
| 13 | Q3 | **Plot 2's** denominator, its pooling of the arms, and the interval method | **Plot 2 divides by the 225 unique subjects in ADAE, following the supplied sample output — not by the table's 254.** The sample figure is labelled "n = 225 subjects" and ADAE contains exactly that many unique `USUBJID`, so the sample fixes the denominator for this figure. It is worth being explicit that this is not the more conventional clinical choice: an incidence rate normally divides by everyone who could have reported the event, which is the Safety population the summary table uses (note 11). Dividing by 225 counts only subjects who had at least one adverse event, omitting the 29 treated subjects who had none, and so raises every rate by a factor of 1.129; both denominators are printed in the run log so the difference is visible rather than buried. The arms are pooled — one point estimate and one interval per event, as "the top 10 most frequent AEs with 95% CI for incidence rates" implies; a per-arm reading would answer a comparative question the spec does not pose, and pooling is what makes "top 10" well defined. Intervals come from `stats::binom.test()`, the established exact binomial implementation, per note 5; nothing is hand-rolled and no normal approximation is used, which matters at the low incidences seen here. |
| 14 | Q4 | Where the LLM sits in the pipeline | **One step only: free text to a validated `QuerySpec`.** The model is confined to one step: turning free text into a `target_column` / `filter_value` pair, returned as a validated Pydantic `QuerySpec` via LangChain's `with_structured_output()`. It never generates code and never receives the data. Everything after the parse is deterministic pandas, so the same question always yields the same rows, and the agent's behaviour can be audited without re-running the model. The allowlist gate between the two halves rejects any column outside the queryable catalogue, so a wrong or adversarial parse cannot reach the dataframe. |
| 15 | Q4 | Behaviour when no API key is present | **Mock fires on a missing key only; a failed call raises.** A missing key selects a deterministic mock parser so the pipeline runs offline, and the active mode is printed at startup with every result tagged `openai` or `mock`. The fallback is deliberately narrow: it covers a missing key only. A key that is present but fails — rate limit, network, bad model name — raises, because silently returning keyword-matched results would make a broken run indistinguishable from a working one. |

*Extend this table as further decisions are made — one row per decision, newest at the
bottom.*

## 8. References

- Subject Disposition aCRF — mock-up eCRF with the General Notes for Question 1:
  https://github.com/pharmaverse/pharmaverseraw/blob/main/vignettes/articles/aCRFs/Subject_Disposition_aCRF.pdf
- CDISC SDTM Implementation Guide v3.4: https://www.cdisc.org/standards/foundational/sdtmig/sdtmig-v3-4
- Pharmaverse examples: https://pharmaverse.github.io/examples/
- `{sdtm.oak}` documentation: https://pharmaverse.github.io/sdtm.oak/
- `{admiral}` documentation: https://pharmaverse.github.io/admiral/
- `{gtsummary}` documentation: https://www.danieldsjoberg.com/gtsummary/
- FDA TLG catalogue: https://pharmaverse.github.io/cardinal/quarto/index-catalog.html

## 9. Ideas for a production version

Scoped out deliberately: the assessment asks for working deliverables, not the
infrastructure that would surround them in a real study.

- **Automated testing.** A `{testthat}` suite for the derivation edge cases — the age-group
  boundaries at 18 and 50, the valid-dose rule including zero-dose placebo, the
  seconds-only imputation case, subject-level versus record-level counting. These are
  currently covered by in-script validation blocks that write to the run logs.
- **CI.** GitHub Actions running the scripts and a linter on push (`r-lib/actions` for R,
  `ruff` or `flake8` for Python), so the logs are regenerated by the pipeline rather than
  by hand.
- **Dependency management.** `renv` for R and `uv` for Python, pinning exact versions
  rather than documenting them in this README.
- **Question 3.** Per-arm incidence with confidence intervals as a companion to the pooled
  figure, supporting the cross-arm comparison the pooled view cannot.
- **Question 4.** An interactive query loop, more mappable columns, and a small evaluation
  set of question/expected-column pairs to measure parse accuracy rather than assume it.
- **Parameterisation.** The study-specific constants — the treatment arm names, the `"01-"`
  `USUBJID` prefix — are literals with comments explaining them. A config file would make
  the scripts reusable across studies.
