import { useState } from 'react';
import { apiRequest } from '../lib/api';

/**
 * SkillMapping.jsx
 * Lets a student paste/upload resume text, optionally pick a target job,
 * and trigger Gemini-powered gap analysis via the FastAPI backend.
 * Displays the structured gap summary + generated learning path modules.
 */
export default function SkillMapping({ profile, jobs = [] }) {
  const [resumeText, setResumeText] = useState('');
  const [targetJobId, setTargetJobId] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [result, setResult] = useState(null);

  async function handleFileUpload(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    // For a hackathon prototype: read plain text directly.
    // For real PDFs/DOCX, parse client-side (e.g. pdfjs-dist) or upload
    // to Supabase Storage and extract text server-side before calling
    // /analyze-resume.
    const text = await file.text();
    setResumeText(text);
  }

  async function handleAnalyze() {
    if (!resumeText.trim()) {
      setError('Please paste or upload your resume text first.');
      return;
    }
    setLoading(true);
    setError(null);
    setResult(null);
    try {
      const data = await apiRequest(`/api/students/${profile.id}/analyze-resume`, {
        method: 'POST',
        body: {
          resume_text: resumeText,
          target_job_id: targetJobId || null,
        },
      });
      setResult(data.gap_analysis);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }

  async function handleCompleteModule(learningPathId, moduleKey) {
    try {
      await apiRequest(`/api/students/${profile.id}/complete-module`, {
        method: 'POST',
        body: { learning_path_id: learningPathId, module_key: moduleKey },
      });
      alert('Module marked complete! Check your dashboard for updated readiness score.');
    } catch (e) {
      setError(e.message);
    }
  }

  return (
    <div className="p-6 max-w-4xl mx-auto space-y-6">
      <h1 className="text-2xl font-bold text-teal-900">Skill Mapping &amp; Gap Analysis</h1>

      <div className="bg-white rounded-2xl shadow p-6 space-y-4">
        <div>
          <label className="block text-sm font-medium text-slate-600 mb-1">
            Upload resume (.txt) or paste resume text
          </label>
          <input
            type="file"
            accept=".txt,.md"
            onChange={handleFileUpload}
            className="block w-full text-sm text-slate-500 mb-2"
          />
          <textarea
            value={resumeText}
            onChange={(e) => setResumeText(e.target.value)}
            rows={8}
            placeholder="Paste your resume text here..."
            className="w-full rounded-xl border border-slate-200 p-3 text-sm focus:outline-none focus:ring-2 focus:ring-teal-500"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-slate-600 mb-1">
            Benchmark against a specific job (optional)
          </label>
          <select
            value={targetJobId}
            onChange={(e) => setTargetJobId(e.target.value)}
            className="w-full rounded-xl border border-slate-200 p-2 text-sm"
          >
            <option value="">General Ayush industry benchmark</option>
            {jobs.map((job) => (
              <option key={job.id} value={job.id}>
                {job.title} — {job.company}
              </option>
            ))}
          </select>
        </div>

        <button
          onClick={handleAnalyze}
          disabled={loading}
          className="bg-teal-700 hover:bg-teal-800 disabled:opacity-50 text-white font-medium px-5 py-2 rounded-xl transition"
        >
          {loading ? 'Analyzing with Gemini…' : 'Run Gap Analysis'}
        </button>

        {error && <p className="text-red-600 text-sm">{error}</p>}
      </div>

      {result && <GapAnalysisResult result={result} onCompleteModule={handleCompleteModule} />}
    </div>
  );
}

function GapAnalysisResult({ result, onCompleteModule }) {
  return (
    <div className="space-y-6">
      <div className="bg-teal-50 border border-teal-200 rounded-2xl p-5">
        <h2 className="font-semibold text-teal-900 mb-1">Summary</h2>
        <p className="text-sm text-teal-800">{result.gap_summary}</p>
      </div>

      <div className="grid md:grid-cols-2 gap-4">
        <div className="bg-white rounded-2xl shadow p-5">
          <h3 className="font-semibold text-slate-700 mb-3">Matched Strengths</h3>
          <div className="flex flex-wrap gap-2">
            {(result.matched_strengths || []).map((s) => (
              <span key={s} className="text-xs bg-emerald-100 text-emerald-800 px-3 py-1 rounded-full">
                {s}
              </span>
            ))}
          </div>
        </div>

        <div className="bg-white rounded-2xl shadow p-5">
          <h3 className="font-semibold text-slate-700 mb-3">Identified Gaps</h3>
          <ul className="space-y-2">
            {(result.gaps || []).map((g) => (
              <li key={g.skill} className="text-sm">
                <span className="font-medium">{g.skill}</span>{' '}
                <span
                  className={`text-xs px-2 py-0.5 rounded-full ${
                    g.priority === 'high'
                      ? 'bg-red-100 text-red-700'
                      : g.priority === 'medium'
                      ? 'bg-amber-100 text-amber-700'
                      : 'bg-slate-100 text-slate-600'
                  }`}
                >
                  {g.priority}
                </span>
                <div className="text-xs text-slate-400 mt-0.5">
                  {g.current_level}/100 → target {g.required_level}/100
                </div>
              </li>
            ))}
          </ul>
        </div>
      </div>

      <div className="bg-white rounded-2xl shadow p-5">
        <h3 className="font-semibold text-slate-700 mb-4">Recommended Learning Path</h3>
        <div className="space-y-3">
          {(result.modules || []).map((m, idx) => (
            <div key={m.key} className="border border-slate-100 rounded-xl p-4 flex justify-between items-start">
              <div>
                <p className="font-medium text-slate-800">
                  {idx + 1}. {m.title}
                </p>
                <p className="text-sm text-slate-500">{m.description}</p>
                <p className="text-xs text-slate-400 mt-1">
                  Targets: {m.target_skill} · ~{m.estimated_hours}h
                </p>
              </div>
              <button
                onClick={() => onCompleteModule(result.learning_path_id, m.key)}
                className="text-xs font-medium text-teal-700 border border-teal-600 rounded-lg px-3 py-1 hover:bg-teal-50 whitespace-nowrap"
              >
                Mark Complete
              </button>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
