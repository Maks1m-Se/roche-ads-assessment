"""
Question 4 (bonus) - GenAI clinical data assistant.

Translates a free-text clinical question about an adverse event dataset into a
structured query, executes it deterministically with pandas, and returns the
number of unique subjects affected plus their subject IDs.

Design: exactly one non-deterministic step. The LLM only chooses *which column*
and *which value* to filter on; it never writes code, never sees the dataframe,
and never touches the result. Everything after the parse is ordinary pandas.

    NL question
      -> LLM parse (LangChain with_structured_output)
      -> QuerySpec (Pydantic, validated)
      -> allowlist gate (column must exist in the dataframe)
      -> deterministic pandas filter
      -> QueryResult

Data note: the input file is named adae.csv, but it is exported from
pharmaversesdtm::ae - an SDTM AE dataset, not an ADaM ADAE. That mismatch is the
assessment's own; the file name is kept verbatim as specified. The columns the
agent maps onto (AESEV, AETERM, AESOC) all exist in SDTM AE.

Author: Maksim Sendetski
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from pydantic import BaseModel, Field

# Verified against the installed versions: langchain 1.4.0, langchain-core 1.6.2,
# langchain-openai 1.6.0, pydantic 2.13.5, pandas 2.1.1, python-dotenv 1.2.3.
from langchain_openai import ChatOpenAI

DATA_FILE = Path(__file__).with_name("adae.csv")

# Default model. Overridable with OPENAI_MODEL so the script does not need
# editing when model names change.
DEFAULT_MODEL = os.environ.get("OPENAI_MODEL", "gpt-4o-mini")

# The only columns the agent is ever allowed to filter on. This list is the
# safety boundary's whitelist half; the other half is the runtime check that the
# column actually exists in the loaded dataframe (see _validate_spec).
MAPPABLE_COLUMNS: dict[str, str] = {
    "AESEV": (
        "Severity or intensity of the adverse event. "
        "Values are MILD, MODERATE, SEVERE."
    ),
    "AETERM": (
        "The specific adverse event as reported, a single symptom or diagnosis. "
        "Examples: HEADACHE, NAUSEA, DIZZINESS, RASH."
    ),
    "AESOC": (
        "System organ class - the body system the event belongs to. "
        "Examples: CARDIAC DISORDERS, NERVOUS SYSTEM DISORDERS, "
        "GASTROINTESTINAL DISORDERS."
    ),
}

SUBJECT_ID = "USUBJID"


# ------------------------------------------------------------------------------
# Structured output schema
# ------------------------------------------------------------------------------


class QuerySpec(BaseModel):
    """A clinical question reduced to a single column/value filter.

    The field descriptions are not decoration: LangChain converts this class into
    a JSON schema and sends it to the model, so these strings are what steer the
    parse.
    """

    target_column: str = Field(
        description=(
            "Which dataset column answers the question. Must be exactly one of: "
            "AESEV, AETERM, AESOC."
        )
    )
    filter_value: str = Field(
        description=(
            "The value to match in that column, in the dataset's own uppercase "
            "form. For example MODERATE for a severity question, HEADACHE for a "
            "specific event, CARDIAC DISORDERS for a body system."
        )
    )


@dataclass
class QueryResult:
    """The full trace of one question, from text to subjects."""

    question: str
    spec: QuerySpec
    source: str  # "openai" or "mock" - which parser produced the spec
    subject_count: int
    subject_ids: list[str] = field(default_factory=list)

    def summary(self) -> str:
        head = ", ".join(self.subject_ids[:5])
        more = f", ... (+{len(self.subject_ids) - 5} more)" if len(self.subject_ids) > 5 else ""
        return (
            f"{self.spec.target_column} == '{self.spec.filter_value}' "
            f"[{self.source}] -> {self.subject_count} subjects"
            + (f": {head}{more}" if self.subject_ids else "")
        )


class InvalidQueryColumnError(ValueError):
    """Raised when the parse names a column the agent is not allowed to filter."""


# ------------------------------------------------------------------------------
# Prompt
# ------------------------------------------------------------------------------


def _column_catalogue() -> str:
    return "\n".join(f"- {name}: {desc}" for name, desc in MAPPABLE_COLUMNS.items())


SYSTEM_PROMPT = f"""You translate questions about a clinical trial adverse event \
dataset into a single column filter.

The dataset has these queryable columns:
{_column_catalogue()}

Rules:
- Choose target_column from that list only. Never invent a column name.
- Return the value in the dataset's uppercase form.
- Return only the two fields target_column and filter_value. Nothing else.

Examples:
- "subjects with severe adverse events" -> AESEV / SEVERE
- "who had nausea" -> AETERM / NAUSEA
- "patients with nervous system disorders" -> AESOC / NERVOUS SYSTEM DISORDERS
"""


# ------------------------------------------------------------------------------
# Mock parser - used only when no API key is configured
# ------------------------------------------------------------------------------

# Deterministic stand-in so the pipeline is demonstrable without a key. Keyword
# matching here is acceptable precisely because it is NOT the product: it exists
# so the deterministic half of the agent can be exercised offline. The real
# mapping is the LLM's job.
_MOCK_RULES: list[tuple[tuple[str, ...], str, str]] = [
    (("mild",), "AESEV", "MILD"),
    (("moderate",), "AESEV", "MODERATE"),
    (("severe", "severity"), "AESEV", "SEVERE"),
    (("headache",), "AETERM", "HEADACHE"),
    (("nausea",), "AETERM", "NAUSEA"),
    (("dizziness", "dizzy"), "AETERM", "DIZZINESS"),
    (("cardiac", "heart"), "AESOC", "CARDIAC DISORDERS"),
    (("nervous system",), "AESOC", "NERVOUS SYSTEM DISORDERS"),
    (("gastrointestinal", "gi "), "AESOC", "GASTROINTESTINAL DISORDERS"),
]


def _mock_parse(question: str) -> QuerySpec:
    text = question.lower()
    for keywords, column, value in _MOCK_RULES:
        if any(k in text for k in keywords):
            return QuerySpec(target_column=column, filter_value=value)
    # No rule matched. Return something structurally valid but obviously unmatched,
    # rather than guessing - the empty result is the honest answer offline.
    return QuerySpec(target_column="AETERM", filter_value="UNKNOWN")


# ------------------------------------------------------------------------------
# Agent
# ------------------------------------------------------------------------------


class ClinicalTrialDataAgent:
    """Answers free-text questions about an adverse event dataset."""

    def __init__(self, data_file: Path | str = DATA_FILE, model: str = DEFAULT_MODEL):
        load_dotenv()

        self.data_file = Path(data_file)
        if not self.data_file.exists():
            raise FileNotFoundError(
                f"{self.data_file} not found. Generate it from R with:\n"
                '  write.csv(pharmaversesdtm::ae, "question_4_genai/adae.csv", '
                "row.names = FALSE)"
            )
        self.df = pd.read_csv(self.data_file)

        missing = [c for c in (*MAPPABLE_COLUMNS, SUBJECT_ID) if c not in self.df.columns]
        if missing:
            raise ValueError(f"{self.data_file} is missing required columns: {missing}")

        self.model_name = model
        # load_dotenv() above has already copied .env into os.environ, so this
        # lookup sees both sources and the mock path is taken only when the key is
        # absent from each. Clearing OPENAI_API_KEY in the shell is therefore not
        # enough to force the offline path - .env still supplies it, and the run
        # will make real API calls. Rename or remove .env to force the mock.
        api_key = os.environ.get("OPENAI_API_KEY")
        self.use_llm = bool(api_key)

        if self.use_llm:
            print(f"[LLM] Using real OpenAI model: {self.model_name}")
            # with_structured_output() returns a Runnable that yields a validated
            # QuerySpec instance. Verified present in langchain-openai 1.6.0.
            self._parser = ChatOpenAI(
                model=self.model_name,
                api_key=api_key,
                temperature=0,
            ).with_structured_output(QuerySpec)
        else:
            print("[LLM] No OPENAI_API_KEY found - using mock responses.")
            self._parser = None

    # -- step 1: parse ---------------------------------------------------------

    def parse_question(self, question: str) -> tuple[QuerySpec, str]:
        """Turn free text into a QuerySpec. Returns (spec, source)."""
        # The mock is chosen here and only here: on the absence of a key, decided
        # once at construction. A missing key is a *configuration* state, known
        # before any work is attempted, and the offline path is a legitimate way
        # to run this program - so falling back to it is honest.
        if not self.use_llm:
            return _mock_parse(question), "mock"

        # Deliberately no try/except around the call below.
        #
        # The tempting version wraps this in `except Exception: return
        # _mock_parse(...)`, so the demo never crashes. That would be the wrong
        # trade here. A rate limit, an expired key, a network failure or a
        # retired model name are all *runtime faults*, not configuration
        # choices, and the keyword table would answer the three rehearsed
        # example questions correctly even while the model was completely
        # unreachable. The transcript would then show plausible results for a run
        # in which the LLM - the entire point of the exercise - never
        # participated. Nobody reading the log could tell the two apart.
        #
        # Failing loudly costs a stack trace. Failing quietly costs the reader's
        # ability to trust every other line of the output. The `source` tag on
        # each result narrows the window further but does not close it, since a
        # per-call fallback would have to tag itself "mock" mid-run and could
        # easily be skimmed past.
        spec = self._parser.invoke(
            [("system", SYSTEM_PROMPT), ("human", question)]
        )
        return spec, "openai"

    # -- step 2: the safety boundary -------------------------------------------

    def _validate_spec(self, spec: QuerySpec) -> str:
        """Allowlist gate. Nothing downstream of here trusts the model.

        Two checks, both required. The first confines the query to columns this
        agent is designed to answer over; the second confirms that column really
        exists in the loaded data, so a stale allowlist cannot produce a KeyError
        deep inside the filter. Only a string that clears both is ever used to
        index the dataframe - there is no eval(), no query string built from
        model output, and no model-generated code executed anywhere.
        """
        # Normalised before testing, not after: the model may answer "aesev" or
        # " AESEV ". Those are the same column and should pass, so the gate
        # compares the normalised form and returns it, guaranteeing that the
        # exact string tested is the exact string later used to index the frame.
        # Validating one spelling and indexing with another is how allowlists
        # develop holes.
        column = spec.target_column.strip().upper()

        # Check one - is this a column the agent is *willing* to answer over?
        #
        # An allowlist, not a denylist. The set of harmful inputs is unbounded
        # and unknowable; the set of columns this agent answers questions about
        # is three entries long and written down. Only the second is worth
        # enumerating. This also blocks perfectly real columns like USUBJID or
        # AESER - not because they are dangerous, but because the agent has no
        # prompt describing them and would be guessing at their values.
        if column not in MAPPABLE_COLUMNS:
            raise InvalidQueryColumnError(
                f"Model returned column '{spec.target_column}', which is not "
                f"queryable. Allowed columns: {', '.join(MAPPABLE_COLUMNS)}."
            )

        # Check two - does the column actually exist in the data loaded now?
        #
        # Redundant only while the catalogue and the CSV agree. They are two
        # separate artefacts that drift independently: the catalogue is edited
        # here, the CSV is regenerated from R. If someone adds a column to
        # MAPPABLE_COLUMNS that the export does not carry, the first check waves
        # it through and pandas raises a bare KeyError from inside the filter -
        # an error about the data that is really an error about configuration.
        # This check turns that into a message naming the file and the column.
        if column not in self.df.columns:
            raise InvalidQueryColumnError(
                f"Column '{column}' is allowlisted but absent from "
                f"{self.data_file.name}."
            )
        return column

    # -- step 3: execute -------------------------------------------------------

    def execute(self, spec: QuerySpec) -> tuple[int, list[str]]:
        """Run the validated filter. Pure pandas, fully deterministic."""
        column = self._validate_spec(spec)

        # Normalise the value the same way on both sides of the comparison.
        #
        # SDTM stores these fields uppercase - MODERATE, HEADACHE, CARDIAC
        # DISORDERS - but the model is a language model, and the casing it
        # returns tracks the question it was asked. "Moderate severity" in the
        # prompt invites "Moderate" back, and the surrounding whitespace of a
        # generated string is not something to rely on either. None of that
        # changes which subjects the reader is asking about.
        #
        # The alternative - an exact match - would fail silently and in the worst
        # possible way: zero subjects, no error, a result that looks like a
        # clinical finding ("nobody had moderate events") when it is really a
        # string-casing artefact. Empty results are legitimate here, which is
        # exactly why they must never be manufactured by formatting.
        #
        # This is normalisation, not fuzzy matching. "MODERATE" still has to
        # equal "MODERATE"; a misspelling or a wrong term still returns nothing,
        # because guessing what the model meant is not this layer's job.
        wanted = spec.filter_value.strip().upper()

        # astype(str) guards the column side: a CSV column that happens to parse
        # as numeric, or that carries NaN, has no .str accessor otherwise.
        matches = self.df[self.df[column].astype(str).str.upper() == wanted]

        # An empty match is a legitimate answer - no subject had that event - and
        # is returned as a count of zero, not raised as an error.
        subject_ids = sorted(matches[SUBJECT_ID].dropna().unique().tolist())
        return len(subject_ids), subject_ids

    # -- end to end ------------------------------------------------------------

    def ask(self, question: str) -> QueryResult:
        spec, source = self.parse_question(question)
        count, subject_ids = self.execute(spec)
        return QueryResult(
            question=question,
            spec=spec,
            source=source,
            subject_count=count,
            subject_ids=subject_ids,
        )


if __name__ == "__main__":
    agent = ClinicalTrialDataAgent()
    print(agent.ask("Which subjects had headache?").summary())
