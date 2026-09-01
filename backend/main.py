"""
Ministry of Ayush — Academia-Industry Collaboration Portal
FastAPI backend entrypoint.

Deploy target: Render (see render.yaml).
Frontend: React/Vite on Vercel (CORS configured below).
DB/Auth: Supabase (Postgres). This service uses the Supabase Python
client with the service-role key for trusted server-side operations,
while the frontend talks to Supabase directly (with the anon key) for
plain CRUD that RLS already protects. FastAPI is used for anything
that needs the Gemini API, cross-table business logic (matching,
unlocking), or operations that must bypass RLS safely.
"""

import os
from datetime import datetime
from typing import Optional, List

from dotenv import load_dotenv
from fastapi import FastAPI, Depends, HTTPException, Header, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from supabase import create_client, Client

# Loads backend/.env when running locally; on Render, env vars are
# already injected by the platform, so this call is a harmless no-op.
load_dotenv()

from ai_agent import (
    analyze_skill_gap,
    chat_with_study_bot,
    generate_flowchart_and_quiz,
)

# ---------------------------------------------------------------------
# Supabase client (service role — server-side trusted operations only)
# ---------------------------------------------------------------------
SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_SERVICE_ROLE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

# ---------------------------------------------------------------------
# App + CORS
# ---------------------------------------------------------------------
app = FastAPI(title="Ayush Academia-Industry Portal API", version="1.0.0")

ALLOWED_ORIGINS = [
    "https://ayush-portal1.vercel.app/"            # Vercel preview deployments (see note below)
]

app.add_middleware(
    CORSMiddleware,
    # NOTE: starlette's CORSMiddleware does not support wildcards mid-string
    # for allow_origins. For Vercel preview URLs, either list exact domains,
    # set your custom domain as the only allowed origin, or use
    # allow_origin_regex instead (uncomment below).
    allow_origins=[o for o in ALLOWED_ORIGINS if "*" not in o],
    allow_origin_regex=r"https://ayush-portal.*\.vercel\.app",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------
# Auth dependency — verifies the Supabase JWT sent from the frontend
# ---------------------------------------------------------------------
async def get_current_user(authorization: Optional[str] = Header(None)) -> dict:
    """
    Expects `Authorization: Bearer <supabase_access_token>`.
    Verifies the token against Supabase Auth and returns the user +
    their profile (role, institution, etc.) for use in route handlers.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")

    token = authorization.removeprefix("Bearer ").strip()
    try:
        user_resp = supabase.auth.get_user(token)
        user = user_resp.user
        if not user:
            raise ValueError("No user found for token")
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token")

    profile = (
        supabase.table("profiles").select("*").eq("id", user.id).single().execute()
    )
    if not profile.data:
        raise HTTPException(status_code=404, detail="Profile not found for user")

    return {"auth_user": user, "profile": profile.data}


def require_role(*roles: str):
    async def _dep(current=Depends(get_current_user)):
        if current["profile"]["role"] not in roles:
            raise HTTPException(status_code=403, detail="Insufficient role permissions")
        return current

    return _dep


# ---------------------------------------------------------------------
# Pydantic schemas
# ---------------------------------------------------------------------
class ResumeAnalysisRequest(BaseModel):
    resume_text: str = Field(..., description="Raw extracted resume text")
    target_job_id: Optional[str] = Field(None, description="Job to benchmark against, if any")


class SkillEntry(BaseModel):
    name: str
    proficiency: int = Field(..., ge=0, le=100)


class ModuleCompletionRequest(BaseModel):
    learning_path_id: str
    module_key: str


class ChatRequest(BaseModel):
    message: str
    history: Optional[List[dict]] = None  # [{role: "user"|"assistant", content: str}]


class NotesRequest(BaseModel):
    title: str
    raw_notes: str


class ApplyRequest(BaseModel):
    job_id: str


# ---------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------
@app.get("/")
def health():
    return {"status": "ok", "service": "ayush-portal-api", "time": datetime.utcnow().isoformat()}


# =======================================================================
# 1. SKILL MAPPING & GAP ANALYSIS
# =======================================================================
@app.post("/api/students/{student_id}/analyze-resume")
async def analyze_resume(
    student_id: str,
    payload: ResumeAnalysisRequest,
    current=Depends(get_current_user),
):
    """
    Sends resume text + current skill profile to Gemini, gets back a
    structured gap analysis + learning path, and persists it.
    """
    if current["profile"]["id"] != student_id and current["profile"]["role"] not in ("academician", "admin"):
        raise HTTPException(status_code=403, detail="Not authorized for this student")

    # Fetch student's declared skills for context
    existing_skills = (
        supabase.table("student_skills")
        .select("proficiency, skills(name, category)")
        .eq("student_id", student_id)
        .execute()
    ).data

    # Fetch target job's required skills, if provided
    target_job = None
    if payload.target_job_id:
        job_resp = (
            supabase.table("jobs")
            .select("title, company, job_required_skills(min_proficiency, skills(name))")
            .eq("id", payload.target_job_id)
            .single()
            .execute()
        )
        target_job = job_resp.data

    gap_result = analyze_skill_gap(
        resume_text=payload.resume_text,
        existing_skills=existing_skills,
        target_job=target_job,
    )

    # Persist resume + learning path
    supabase.table("resumes").insert(
        {"student_id": student_id, "raw_text": payload.resume_text}
    ).execute()

    lp_insert = (
        supabase.table("learning_paths")
        .insert(
            {
                "student_id": student_id,
                "target_job_id": payload.target_job_id,
                "gap_summary": gap_result.get("gap_summary"),
                "modules": gap_result.get("modules", []),
            }
        )
        .execute()
    )

    # Seed module_progress rows as "locked" (first module unlocked)
    modules = gap_result.get("modules", [])
    progress_rows = [
        {
            "student_id": student_id,
            "learning_path_id": lp_insert.data[0]["id"],
            "module_key": m["key"],
            "status": "in_progress" if i == 0 else "locked",
        }
        for i, m in enumerate(modules)
    ]
    if progress_rows:
        supabase.table("module_progress").insert(progress_rows).execute()

    return {"learning_path": lp_insert.data[0], "gap_analysis": gap_result}


@app.get("/api/students/{student_id}/skill-gap-summary")
async def get_skill_gap_summary(student_id: str, current=Depends(get_current_user)):
    lp = (
        supabase.table("learning_paths")
        .select("*")
        .eq("student_id", student_id)
        .order("generated_at", desc=True)
        .limit(1)
        .execute()
    )
    if not lp.data:
        raise HTTPException(status_code=404, detail="No learning path found yet")
    return lp.data[0]


# =======================================================================
# 2. AUTOMATED OPPORTUNITY UNLOCKING
# =======================================================================
def compute_match_score(student_id: str, job_id: str) -> float:
    """Weighted overlap between a student's skills and a job's required skills."""
    required = (
        supabase.table("job_required_skills")
        .select("skill_id, min_proficiency, weight")
        .eq("job_id", job_id)
        .execute()
    ).data
    if not required:
        return 0.0

    student_skills = {
        row["skill_id"]: row["proficiency"]
        for row in supabase.table("student_skills")
        .select("skill_id, proficiency")
        .eq("student_id", student_id)
        .execute()
        .data
    }

    total_weight = sum(r["weight"] for r in required)
    achieved = 0.0
    for r in required:
        prof = student_skills.get(r["skill_id"], 0)
        ratio = min(prof / r["min_proficiency"], 1.0) if r["min_proficiency"] else 1.0
        achieved += ratio * r["weight"]

    return round((achieved / total_weight) * 100, 2) if total_weight else 0.0


@app.get("/api/students/{student_id}/matched-opportunities")
async def matched_opportunities(student_id: str, current=Depends(get_current_user)):
    """Returns jobs the student meets the min_readiness_score for, with match scores."""
    profile = supabase.table("profiles").select("readiness_score").eq("id", student_id).single().execute().data
    readiness = profile["readiness_score"]

    jobs = (
        supabase.table("jobs")
        .select("*, job_required_skills(min_proficiency, weight, skills(name))")
        .eq("is_active", True)
        .lte("min_readiness_score", readiness)
        .execute()
    ).data

    results = []
    for job in jobs:
        score = compute_match_score(student_id, job["id"])
        results.append({**job, "match_score": score})

    results.sort(key=lambda j: j["match_score"], reverse=True)
    return {"readiness_score": readiness, "opportunities": results}


@app.post("/api/students/{student_id}/complete-module")
async def complete_module(
    student_id: str, payload: ModuleCompletionRequest, current=Depends(get_current_user)
):
    """Marks a module complete, unlocks the next module, and bumps readiness score."""
    if current["profile"]["id"] != student_id:
        raise HTTPException(status_code=403, detail="Not authorized")

    supabase.table("module_progress").update(
        {"status": "completed", "completed_at": datetime.utcnow().isoformat()}
    ).eq("student_id", student_id).eq(
        "learning_path_id", payload.learning_path_id
    ).eq("module_key", payload.module_key).execute()

    # Unlock next locked module in the same learning path
    remaining = (
        supabase.table("module_progress")
        .select("id, module_key, status")
        .eq("learning_path_id", payload.learning_path_id)
        .eq("status", "locked")
        .order("module_key")
        .limit(1)
        .execute()
    ).data
    if remaining:
        supabase.table("module_progress").update({"status": "in_progress"}).eq(
            "id", remaining[0]["id"]
        ).execute()

    # Recompute a simple readiness score bump (+5, capped at 100)
    profile = supabase.table("profiles").select("readiness_score").eq("id", student_id).single().execute().data
    new_score = min(profile["readiness_score"] + 5, 100)
    supabase.table("profiles").update({"readiness_score": new_score}).eq("id", student_id).execute()

    return {"status": "completed", "new_readiness_score": new_score}


@app.post("/api/students/{student_id}/apply")
async def apply_to_job(student_id: str, payload: ApplyRequest, current=Depends(get_current_user)):
    if current["profile"]["id"] != student_id:
        raise HTTPException(status_code=403, detail="Not authorized")

    score = compute_match_score(student_id, payload.job_id)
    result = (
        supabase.table("applications")
        .insert({"student_id": student_id, "job_id": payload.job_id, "match_score": score})
        .execute()
    )
    return result.data[0]


# =======================================================================
# 3. AI STUDY COMPANION (chat, mermaid flowcharts, quizzes)
# =======================================================================
@app.post("/api/students/{student_id}/study-bot/chat")
async def study_bot_chat(student_id: str, payload: ChatRequest, current=Depends(get_current_user)):
    if current["profile"]["id"] != student_id:
        raise HTTPException(status_code=403, detail="Not authorized")

    reply = chat_with_study_bot(message=payload.message, history=payload.history or [])

    supabase.table("chat_messages").insert(
        [
            {"student_id": student_id, "role": "user", "content": payload.message},
            {"student_id": student_id, "role": "assistant", "content": reply},
        ]
    ).execute()

    return {"reply": reply}


@app.post("/api/students/{student_id}/study-bot/notes")
async def create_note_with_flowchart(
    student_id: str, payload: NotesRequest, current=Depends(get_current_user)
):
    """Takes pasted notes, returns a Mermaid.js flowchart + quiz JSON, and persists it."""
    if current["profile"]["id"] != student_id:
        raise HTTPException(status_code=403, detail="Not authorized")

    result = generate_flowchart_and_quiz(payload.raw_notes)

    note = (
        supabase.table("notes")
        .insert(
            {
                "student_id": student_id,
                "title": payload.title,
                "raw_notes": payload.raw_notes,
                "mermaid_syntax": result["mermaid_syntax"],
                "quiz": result["quiz"],
            }
        )
        .execute()
    )
    return note.data[0]


@app.get("/api/students/{student_id}/notes")
async def list_notes(student_id: str, current=Depends(get_current_user)):
    notes = (
        supabase.table("notes")
        .select("*")
        .eq("student_id", student_id)
        .order("created_at", desc=True)
        .execute()
    )
    return notes.data


# =======================================================================
# 4. NOTIFICATIONS / SCHOLARSHIP DEADLINE ALERTS (called by cron)
# =======================================================================
@app.post("/api/cron/scholarship-alerts")
async def run_scholarship_alert_job(x_cron_secret: Optional[str] = Header(None)):
    """
    Intended to be triggered by a scheduled job (Render Cron Job / GitHub
    Actions schedule) hitting this endpoint daily. Protect with a shared
    secret header, not user auth, since it's a machine-to-machine call.
    """
    expected = os.environ.get("CRON_SECRET")
    if not expected or x_cron_secret != expected:
        raise HTTPException(status_code=401, detail="Invalid cron secret")

    today = datetime.utcnow().date().isoformat()
    scholarships = (
        supabase.table("scholarships")
        .select("*")
        .gte("deadline", today)
        .execute()
    ).data

    students = supabase.table("profiles").select("id, readiness_score").eq("role", "student").execute().data

    created = 0
    for s in scholarships:
        eligible_students = [st for st in students if st["readiness_score"] >= s["min_readiness_score"]]
        for st in eligible_students:
            supabase.table("notifications").insert(
                {
                    "recipient_id": st["id"],
                    "title": f"Scholarship deadline: {s['name']}",
                    "body": f"Applications close on {s['deadline']}. {s.get('eligibility_criteria', '')}",
                    "kind": "scholarship",
                }
            ).execute()
            created += 1

    return {"notifications_created": created, "scholarships_checked": len(scholarships)}


# =======================================================================
# 5. DASHBOARD ANALYTICS
# =======================================================================
@app.get("/api/analytics/dashboard")
async def dashboard_analytics(current=Depends(require_role("academician", "admin", "recruiter"))):
    """Aggregate stats for the academician/recruiter analytics dashboard."""
    students = supabase.table("profiles").select("readiness_score").eq("role", "student").execute().data
    scores = [s["readiness_score"] for s in students] or [0]

    applications = supabase.table("applications").select("status").execute().data
    status_counts: dict = {}
    for a in applications:
        status_counts[a["status"]] = status_counts.get(a["status"], 0) + 1

    top_skill_gaps = (
        supabase.table("student_skills")
        .select("proficiency, skills(name)")
        .lt("proficiency", 50)
        .execute()
    ).data

    return {
        "total_students": len(students),
        "avg_readiness_score": round(sum(scores) / len(scores), 2),
        "application_status_breakdown": status_counts,
        "common_skill_gaps": top_skill_gaps[:10],
    }
