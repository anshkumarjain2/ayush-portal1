import { useEffect, useState } from 'react';
import { supabase } from './lib/supabaseClient';
import Login from './components/Login';
import Dashboard from './components/Dashboard';
import SkillMapping from './components/SkillMapping';
import StudyBot from './components/StudyBot';

export default function App() {
  const [session, setSession] = useState(null);
  const [profile, setProfile] = useState(null);
  const [jobs, setJobs] = useState([]);
  const [tab, setTab] = useState('dashboard');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setLoading(false);
    });

    const { data: listener } = supabase.auth.onAuthStateChange((_event, newSession) => {
      setSession(newSession);
    });

    return () => listener.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (!session) {
      setProfile(null);
      return;
    }
    loadProfile();
    loadJobs();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session]);

  async function loadProfile() {
    const { data, error } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', session.user.id)
      .single();
    if (!error) setProfile(data);
  }

  async function loadJobs() {
    const { data, error } = await supabase.from('jobs').select('*').eq('is_active', true);
    if (!error) setJobs(data || []);
  }

  async function handleLogout() {
    await supabase.auth.signOut();
  }

  if (loading) return <div className="min-h-screen flex items-center justify-center text-slate-400">Loading…</div>;
  if (!session) return <Login />;
  if (!profile) return <div className="min-h-screen flex items-center justify-center text-slate-400">Setting up your profile…</div>;

  return (
    <div className="min-h-screen bg-slate-50">
      <nav className="bg-white border-b border-slate-100 px-6 py-3 flex items-center justify-between">
        <div className="flex items-center gap-6">
          <span className="font-bold text-teal-800">Ayush Portal</span>
          <button
            onClick={() => setTab('dashboard')}
            className={`text-sm ${tab === 'dashboard' ? 'text-teal-700 font-medium' : 'text-slate-500'}`}
          >
            Dashboard
          </button>
          {profile.role === 'student' && (
            <>
              <button
                onClick={() => setTab('skills')}
                className={`text-sm ${tab === 'skills' ? 'text-teal-700 font-medium' : 'text-slate-500'}`}
              >
                Skill Mapping
              </button>
              <button
                onClick={() => setTab('studybot')}
                className={`text-sm ${tab === 'studybot' ? 'text-teal-700 font-medium' : 'text-slate-500'}`}
              >
                Study Bot
              </button>
            </>
          )}
        </div>
        <div className="flex items-center gap-3">
          <span className="text-sm text-slate-500">{profile.full_name} · {profile.role}</span>
          <button onClick={handleLogout} className="text-sm text-red-600">Log out</button>
        </div>
      </nav>

      {tab === 'dashboard' && <Dashboard profile={profile} />}
      {tab === 'skills' && profile.role === 'student' && <SkillMapping profile={profile} jobs={jobs} />}
      {tab === 'studybot' && profile.role === 'student' && <StudyBot profile={profile} />}
    </div>
  );
}
