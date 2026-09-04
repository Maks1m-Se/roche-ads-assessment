# Personal Glossary — Roche ADS Assessment

Private learning reference. Not for the repo. Append as new terms come up.

---

## Standards & organisations

**CDISC** — Clinical Data Interchange Standards Consortium. The body that defines the data standards regulators expect. Owns SDTM, ADaM, CDASH, controlled terminology.

**SDTM** — Study Data Tabulation Model. The standard structure for *collected* trial data. One fixed schema every sponsor must conform raw data to. This is Q1's target.

**ADaM** — Analysis Data Model. The standard for *analysis-ready* data, built on top of SDTM. Adds derived variables needed for statistics. This is Q2's target (ADSL).

**CDASH** — Clinical Data Acquisition Standards Harmonization. Standard for how data is *collected* (the form side). Sits before SDTM.

**SDTMIG** — SDTM Implementation Guide. The document specifying exactly how each SDTM domain and variable must be built. v3.4 is referenced in the assessment.

**ADaMIG** — the equivalent implementation guide for ADaM.

---

## Data-collection artifacts

**eCRF** — electronic Case Report Form. The digital form clinic staff fill in per patient visit. Human-friendly, company-specific.

**aCRF** — annotated CRF. The eCRF with annotations showing how each collected field maps to SDTM variables. The bridge between collection and submission. (Your `Subject_Disposition_aCRF.pdf`.)

**EDC** — Electronic Data Capture. The system that runs the eCRFs and stores collected data. Differs per company — the reason SDTM exists to standardise across them.

---

## Data stages (the pipeline)

**raw** — data as collected, pre-standardisation. eCRF field names, uncontrolled terminology, non-ISO dates. (`pharmaverseraw::ds_raw`.)

**SDTM domain** — raw data conformed to the CDISC canonical schema. (`pharmaversesdtm::ds`.)

**ADaM dataset** — SDTM data plus analysis-ready derivations. (`pharmaverseadam::adsl`.)

**TLG / TLF** — Tables, Listings, and Graphs (Figures). The reporting outputs built from ADaM for regulatory submission. Q3.

Flow: **raw → SDTM → ADaM → TLG**. Q1→Q2→Q3 walk this pipeline.

---

## Controlled terminology

**Controlled terminology (CT)** — mandated standardised vocabularies. Maps a collected value ("Complete") to its official CDISC term ("COMPLETED"). Not string cleaning — a governed, traceable lookup.

**codelist** — one named set of allowed values within CT. Identified by a C-code.

**C66727** — the codelist for disposition completion/discontinuation reasons. Used for `DSDECOD` in Q1.

**study_ct** — the study's controlled terminology table. Columns: `codelist_code`, `term_code`, `term_value` (official CDISC term), `collected_value` (as the form phrased it), `term_preferred_term`, `term_synonyms`.

---

## SDTM structural concepts

**domain** — one table in SDTM, covering one topic. Named with a 2-letter code (DS, AE, DM, VS, EX).

**variable naming** — most SDTM variables are prefixed with the domain code. In DS: `DSTERM`, `DSDECOD`, `DSSEQ`. The `--` in docs (e.g. `--SEQ`) is a placeholder for the domain prefix.

---

## The domains in this assessment

**DS** — Disposition. How/why a subject leaves each trial phase (randomised, completed, withdrew). Q1.

**DM** — Demographics. One row per subject. Holds `RFSTDTC` (reference start date) and `ARM`. Needed as a supporting input in Q1 and Q2.

**AE** — Adverse Events. Undesirable events during the trial. Q2 input, Q3 subject.

**VS** — Vital Signs. Q2 input.

**EX** — Exposure. Treatment administration records. Q2 input.

---

## DS variables (Q1 target — 12 required)

**STUDYID** — study identifier. Here `CDISCPILOT01`.

**DOMAIN** — the 2-letter domain code. Always `"DS"` in this domain.

**USUBJID** — Unique Subject Identifier. Constructed: `"01-" + PATNUM`. Consistent across all domains so they can be joined.

**DSSEQ** — sequence number of a record within a subject. Distinguishes a subject's multiple DS records.

**DSTERM** — the reported/collected disposition term, verbatim. What was written on the form.

**DSDECOD** — the standardised (decoded) disposition term. `DSTERM` after controlled terminology is applied.

**DSCAT** — category of the disposition event. Here: `PROTOCOL MILESTONE`, `DISPOSITION EVENT`, or `OTHER EVENT`.

**VISITNUM** — visit number (numeric). From the `VISITNUM` codelist.

**VISIT** — visit name (text, uppercase). From the `VISIT` codelist.

**DSDTC** — date/time the record was *collected*. ISO8601.

**DSSTDTC** — start date/time of the disposition *event* itself. ISO8601. (Not the same as DSDTC.)

**DSSTDY** — study day: days from the subject's reference start (`RFSTDTC`) to the event. Derived, requires DM.

---

## Q2 target variables (ADSL — the four extras)

**AGEGR9 / AGEGR9N** — age group (text / numeric): `<18`, `18-50`, `>50` = 1/2/3.

**TRTSDTM / TRTSTMF** — treatment start datetime / its imputation flag. First valid-dose exposure.

**ITTFL** — Intent-To-Treat flag. `"Y"` if `DM.ARM` is populated, else `"N"`.

**LSTAVLDT** — last known alive date. Max across vital signs, AE onset, disposition, and exposure dates.

*(Note: general ADaM convention often spells this `LSTALVDT`; the assessment uses `LSTAVLDT`. Use the assessment's spelling.)*

---

## sdtm.oak functions (verified in v0.2.0)

**`generate_oak_id_vars()`** — sets up internal record IDs everything joins on.

**`assign_no_ct()`** — map raw → target, no controlled terminology.

**`assign_ct()`** — map raw → target *with* controlled terminology recoding. Args: `ct_spec`, `ct_clst`.

**`hardcode_no_ct()`** — write a fixed value into the target.

**`hardcode_ct()`** — fixed value, terminology-checked.

**`assign_datetime()`** — map date/time components.

**`create_iso8601()`** — convert to ISO8601 format.

**`condition_add()`** — restrict a raw dataset to rows matching a condition (the if/else mechanism).

**`derive_seq()`** — derive the `--SEQ` variable. Arg `rec_vars` defines record ordering.

**`derive_study_day()`** — derive study day. Needs `dm_domain`, `refdt`, `tgdt`.

**`read_ct_spec()`** — read a controlled terminology spec file.

---

## Abbreviations quick list

| Abbr | Meaning |
|---|---|
| CDISC | Clinical Data Interchange Standards Consortium |
| SDTM | Study Data Tabulation Model |
| ADaM | Analysis Data Model |
| CDASH | Clinical Data Acquisition Standards Harmonization |
| eCRF | electronic Case Report Form |
| aCRF | annotated CRF |
| EDC | Electronic Data Capture |
| CT | Controlled Terminology |
| TLG | Tables, Listings, Graphs |
| DS | Disposition (domain) |
| DM | Demographics (domain) |
| AE | Adverse Events (domain) |
| VS | Vital Signs (domain) |
| EX | Exposure (domain) |
| ADSL | Subject-Level Analysis Dataset |
| ITT | Intent To Treat |
| ISO8601 | date/time standard format (YYYY-MM-DD) |

**DSSTDTC vs DSDTC** — DSSTDTC = when the disposition *event* occurred.
DSDTC = when the record was *collected*. Different dates, different sources.

**IT. prefix** — marks a raw eCRF *item* (form field) in the collection layer.
Present on raw inputs (IT.DSDECOD), absent on SDTM outputs (DSDECOD).
A visual tell for raw vs standardised — but not applied consistently to all raw fields.
