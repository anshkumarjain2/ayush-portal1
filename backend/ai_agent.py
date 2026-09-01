"""
ai_agent.py — Gemini-powered intelligence for the Ayush Academia-Industry
Collaboration Portal.

Uses the `google-genai` SDK. Requires GEMINI_API_KEY in the environment.

Responsibilities:
  1. analyze_skill_gap()      -> structured JSON gap analysis + learning path
  2. chat_with_study_bot()    -> conversational AI study companion
  3. generate_flowchart_and_quiz() -> Mermaid.js flowchart + quiz from notes
"""

import os
import json
import re
from typing import Optional, List, Dict, Any

from google import genai
from google.genai import types

GEMINI_API_KEY = os.environ["GEMINI_API_KEY"]
MODEL_NAME = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash")

client = genai.Client(api_key=GEMINI_API_KEY)


# ---------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------
def _extract_json(text: str) -> Dict[str, Any]:
    """
    Gemini sometimes wraps JSON in ```json fences even when told not to.
    This strips fences and parses defensively.
    """
    cleaned = re.sub(r"^```json\s*|^```\s*|```$", "", text.strip(), flags=re.MULTILINE).strip()
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        # Last resort: find the first {...} block
        match = re.search(r"\{.*\}", cleaned, re.DOTALL)
        if match:
            return json.loads(match.group(0))
        raise


# ---------------------------------------------------------------------
# 1. Skill Gap Analysis -> Structured Learning Path
# ---------------------------------------------------------------------
GAP_ANALYSIS_SCHEMA_HINT = """
Return ONLY valid JSON (no markdown fences, no commentary) matching this shape:
{
  "gap_summary": "2-3 sentence plain-English summary of the student's biggest skill gaps",
  "matched_strengths": ["skill name", ...],
  "gaps": [
    {"skill": "skill name", "current_level": 0-100, "required_level": 0-100, "priority": "high|medium|low"}
  ],
  "modules": [
    {
      "key": "short_snake_case_id",
      "title": "Module title",
      "description": "1-2 sentence description",
      "target_skill": "skill name this module improves",
      "estimated_hours": 4,
      "resources": ["resource or topic name", ...]
    }
  ]
}
Order modules by priority (highest-impact gap first). Produce 3-6 modules.
"""


def analyze_skill_gap(
    resume_text: str,
    existing_skills: Optional[List[dict]] = None,
    target_job: Optional[dict] = None,
) -> Dict[str, Any]:
    """
    Calls Gemini to compare a student's resume/skills against either a
    specific target job's required skills, or general industry benchmarks
    for the Ayush sector if no target job is given.
    """
    existing_skills = existing_skills or []
    skills_context = "\n".join(
        f"- {row['skills']['name']} ({row['skills']['category']}): {row['proficiency']}/100"
        for row in existing_skills
        if row.get("skills")
    ) or "No self-assessed skills on file yet."

    if target_job:
        job_context = (
            f"Target job: {target_job['title']} at {target_job['company']}.\n"
            "Required skills:\n"
            + "\n".join(
                f"- {rs['skills']['name']}: minimum proficiency {rs['min_proficiency']}/100"
                for rs in target_job.get("job_required_skills", [])
            )
        )
    else:
        job_context = (
            "No specific target job given. Benchmark against typical requirements "
            "for entry-level roles in the Ayush / traditional-medicine industry "
            "(e.g. Ayurvedic pharmacology, regulatory affairs, clinical research, "
            "herbal product formulation, quality control/GMP, digital health records)."
        )

    prompt = f"""
You are an expert career counselor and curriculum designer for the Ministry of
Ayush's academia-industry collaboration portal. Analyze this student's resume
and current skills, identify gaps against the benchmark below, and design a
personalized learning path to close those gaps.

STUDENT RESUME TEXT:
\"\"\"{resume_text}\"\"\"

STUDENT'S CURRENT SKILL PROFICIENCIES:
{skills_context}

BENCHMARK:
{job_context}

{GAP_ANALYSIS_SCHEMA_HINT}
"""

    response = client.models.generate_content(
        model=MODEL_NAME,
        contents=prompt,
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
            temperature=0.4,
        ),
    )

    return _extract_json(response.text)


# ---------------------------------------------------------------------
# 2. AI Study Companion Chatbot
# ---------------------------------------------------------------------
STUDY_BOT_SYSTEM_INSTRUCTION = """
You are "Ayush StudyBot", a friendly, encouraging AI study companion for
students on an academia-industry collaboration portal focused on the Ayush
(Ayurveda, Yoga, Unani, Siddha, Homeopathy) sector. You help students
understand concepts, prepare for assessments, and connect what they're
studying to real industry skills. Keep answers concise, use simple language,
and where useful suggest a follow-up action (e.g. "want me to turn this into
a flowchart or quiz?").
"""


def chat_with_study_bot(message: str, history: Optional[List[dict]] = None) -> str:
    history = history or []
    contents = []
    for turn in history:
        role = "user" if turn.get("role") == "user" else "model"
        contents.append(types.Content(role=role, parts=[types.Part(text=turn.get("content", ""))]))
    contents.append(types.Content(role="user", parts=[types.Part(text=message)]))

    response = client.models.generate_content(
        model=MODEL_NAME,
        contents=contents,
        config=types.GenerateContentConfig(
            system_instruction=STUDY_BOT_SYSTEM_INSTRUCTION,
            temperature=0.6,
        ),
    )
    return response.text


# ---------------------------------------------------------------------
# 3. Notes -> Mermaid.js Flowchart + Quiz
# ---------------------------------------------------------------------
NOTES_SCHEMA_HINT = """
Return ONLY valid JSON (no markdown fences, no commentary) matching this shape:
{
  "mermaid_syntax": "flowchart TD\\n  A[Start] --> B[...]\\n  ...",
  "quiz": [
    {
      "question": "...",
      "options": ["A", "B", "C", "D"],
      "correct_index": 0,
      "explanation": "why this is correct"
    }
  ]
}
The mermaid_syntax MUST be valid Mermaid.js flowchart syntax (flowchart TD or LR),
using only alphanumeric node ids and square/round brackets for labels — no special
characters that would break Mermaid parsing. Produce 4-6 quiz questions covering
the key concepts in the notes.
"""


def generate_flowchart_and_quiz(raw_notes: str) -> Dict[str, Any]:
    prompt = f"""
A student has pasted the following academic notes. Create:
1. A clear Mermaid.js flowchart (flowchart TD) visualizing the structure,
   sequence, or relationships in these notes.
2. A short quiz (4-6 multiple choice questions) testing understanding of
   the key concepts.

NOTES:
\"\"\"{raw_notes}\"\"\"

{NOTES_SCHEMA_HINT}
"""

    response = client.models.generate_content(
        model=MODEL_NAME,
        contents=prompt,
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
            temperature=0.5,
        ),
    )

    result = _extract_json(response.text)
    # Defensive default in case Gemini omits a field
    result.setdefault("mermaid_syntax", "flowchart TD\n  A[Notes] --> B[Could not generate diagram]")
    result.setdefault("quiz", [])
    return result
