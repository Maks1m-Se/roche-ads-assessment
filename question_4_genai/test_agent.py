"""
Question 4 (bonus) - test script.

Runs one example question per queryable column and prints the full trace of each:
the question asked, the QuerySpec the parse produced, whether that parse came from
OpenAI or the offline mock, the resulting subject count, and the first few subject
IDs.

Run:
    python question_4_genai/test_agent.py

With no OPENAI_API_KEY set this exercises the deterministic half of the pipeline
against the mock parser. With a key in question_4_genai/.env it runs for real.

Author: Maksim Sendetski
"""

from __future__ import annotations

from clinical_agent import ClinicalTrialDataAgent, InvalidQueryColumnError

# One query per mappable column, so a single run demonstrates that the parse can
# tell the three apart: severity vs. a specific reported term vs. a body system.
EXAMPLE_QUESTIONS: list[tuple[str, str]] = [
    ("Give me the subjects who had Adverse events of Moderate severity.", "AESEV"),
    ("Which subjects had headache?", "AETERM"),
    ("Show subjects with cardiac disorders", "AESOC"),
]

RULE = "=" * 78


def main() -> None:
    print(RULE)
    print("Question 4 - GenAI clinical data assistant")
    print(RULE)

    agent = ClinicalTrialDataAgent()
    print(f"[data] {agent.data_file.name}: {len(agent.df):,} adverse event records, "
          f"{agent.df['USUBJID'].nunique()} subjects\n")

    for n, (question, expected_column) in enumerate(EXAMPLE_QUESTIONS, start=1):
        print(f"--- Query {n} " + "-" * 62)
        print(f"  Question       : {question}")
        try:
            result = agent.ask(question)
        except InvalidQueryColumnError as exc:
            # The allowlist gate rejected the parse. Reported, not crashed, so the
            # remaining examples still run.
            print(f"  REJECTED       : {exc}\n")
            continue

        print(f"  Parsed spec    : target_column={result.spec.target_column!r}, "
              f"filter_value={result.spec.filter_value!r}")
        print(f"  Parse source   : {result.source}")
        print(f"  Expected column: {expected_column} "
              f"({'match' if result.spec.target_column == expected_column else 'DIFFERS'})")
        print(f"  Subjects found : {result.subject_count}")
        if result.subject_ids:
            shown = result.subject_ids[:5]
            tail = f"  ... and {len(result.subject_ids) - len(shown)} more" \
                if len(result.subject_ids) > len(shown) else ""
            print(f"  Subject IDs    : {', '.join(shown)}{tail}")
        else:
            print("  Subject IDs    : (none matched)")
        print()

    print(RULE)


if __name__ == "__main__":
    main()
