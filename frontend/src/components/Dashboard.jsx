import { useEffect, useState } from 'react';
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
  PieChart, Pie, Cell, Legend,
} from 'recharts';
import { supabase } from '../lib/supabaseClient';
import { apiRequest } from '../lib/api';

const COLORS = ['#0d9488', '#f59e0b', '#6366f1', '#ef4444', '#10b981'];

/**
 * Dashboard.jsx
 * Renders a role-aware dashboard:
 *  - Student: readiness score, matched opportunities, module progress
 *  - Recruiter/Academician: portal-wide analytics (avg readiness,
 *    application funnel, common skill gaps)
 */
export default function Dashboard({ profile }) {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  // Student-specific state
  const [opportunities, setOpportunities] = useState([]);
  const [readiness, setReadiness] = useState(0);

  // Staff-specific state
  const [analytics, setAnalytics] = useState(null);

  useEffect(() => {
    if (!profile) return;
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [profile]);

  async function load() {
    setLoading(true);
    setError(null);
    try {
      if (profile.role === 'student') {
        const data = await apiRequest(`/api/students/${profile.id}/matched-opportunities`);
        setOpportunities(data.opportunities);
        setReadiness(data.readiness_score);
      } else {
        const data = await apiRequest('/api/analytics/dashboard');
        setAnalytics(data);
      }
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }

  if (loading) return <div className="p-6 text-slate-500">Loading dashboard…</div>;
  if (error) return <div className="p-6 text-red-600">Error: {error}</div>;

  return (
    <div className="p-6 max-w-6xl mx-auto space-y-6">
      <h1 className="text-2xl font-bold text-teal-900">
        {profile.role === 'student' ? `Welcome, ${profile.full_name}` : 'Portal Analytics'}
      </h1>

      {profile.role === 'student' ? (
        <StudentDashboard readiness={readiness} opportunities={opportunities} />
      ) : (
        <StaffDashboard analytics={analytics} />
      )}
    </div>
  );
}

function StudentDashboard({ readiness, opportunities }) {
  return (
    <div className="grid gap-6 md:grid-cols-3">
      <div className="md:col-span-1 bg-white rounded-2xl shadow p-6 flex flex-col items-center justify-center">
        <h2 className="text-sm font-medium text-slate-500 mb-2">Placement Readiness</h2>
        <div className="relative w-32 h-32">
          <svg viewBox="0 0 36 36" className="w-32 h-32 -rotate-90">
            <path
              className="text-slate-100"
              stroke="currentColor"
              strokeWidth="3"
              fill="none"
              d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
            />
            <path
              className="text-teal-600"
              stroke="currentColor"
              strokeWidth="3"
              strokeDasharray={`${readiness}, 100`}
              strokeLinecap="round"
              fill="none"
              d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
            />
          </svg>
          <div className="absolute inset-0 flex items-center justify-center text-2xl font-bold text-teal-800">
            {readiness}%
          </div>
        </div>
      </div>

      <div className="md:col-span-2 bg-white rounded-2xl shadow p-6">
        <h2 className="text-sm font-medium text-slate-500 mb-4">Matched Opportunities</h2>
        <ul className="divide-y divide-slate-100">
          {opportunities.length === 0 && (
            <p className="text-slate-400 text-sm">No opportunities unlocked yet — complete a few learning modules!</p>
          )}
          {opportunities.map((job) => (
            <li key={job.id} className="py-3 flex justify-between items-center">
              <div>
                <p className="font-semibold text-slate-800">{job.title}</p>
                <p className="text-sm text-slate-500">{job.company} · {job.type}</p>
              </div>
              <span className="text-sm font-bold text-teal-700 bg-teal-50 px-3 py-1 rounded-full">
                {job.match_score}% match
              </span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}

function StaffDashboard({ analytics }) {
  if (!analytics) return null;

  const statusData = Object.entries(analytics.application_status_breakdown).map(([status, count]) => ({
    status,
    count,
  }));

  const gapData = analytics.common_skill_gaps.map((g) => ({
    skill: g.skills?.name ?? 'Unknown',
    proficiency: g.proficiency,
  }));

  return (
    <div className="grid gap-6 md:grid-cols-2">
      <div className="bg-white rounded-2xl shadow p-6 flex flex-col justify-center items-center">
        <h2 className="text-sm font-medium text-slate-500 mb-2">Avg. Readiness Score</h2>
        <p className="text-5xl font-bold text-teal-700">{analytics.avg_readiness_score}%</p>
        <p className="text-sm text-slate-400 mt-1">{analytics.total_students} students tracked</p>
      </div>

      <div className="bg-white rounded-2xl shadow p-6">
        <h2 className="text-sm font-medium text-slate-500 mb-4">Application Funnel</h2>
        <ResponsiveContainer width="100%" height={220}>
          <PieChart>
            <Pie data={statusData} dataKey="count" nameKey="status" outerRadius={80} label>
              {statusData.map((_, i) => (
                <Cell key={i} fill={COLORS[i % COLORS.length]} />
              ))}
            </Pie>
            <Legend />
            <Tooltip />
          </PieChart>
        </ResponsiveContainer>
      </div>

      <div className="md:col-span-2 bg-white rounded-2xl shadow p-6">
        <h2 className="text-sm font-medium text-slate-500 mb-4">Common Skill Gaps (proficiency &lt; 50)</h2>
        <ResponsiveContainer width="100%" height={260}>
          <BarChart data={gapData}>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis dataKey="skill" tick={{ fontSize: 12 }} interval={0} angle={-20} textAnchor="end" height={80} />
            <YAxis domain={[0, 100]} />
            <Tooltip />
            <Bar dataKey="proficiency" fill="#f59e0b" radius={[6, 6, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
