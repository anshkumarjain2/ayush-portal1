import { useEffect, useRef, useState } from 'react';
import mermaid from 'mermaid';
import { apiRequest } from '../lib/api';

mermaid.initialize({ startOnLoad: false, theme: 'neutral', securityLevel: 'strict' });

/**
 * StudyBot.jsx
 * Two panes:
 *  1. Chat with the Gemini-powered AI Study Companion
 *  2. Paste notes -> generate a Mermaid.js flowchart + interactive quiz
 *
 * Requires: `npm install mermaid`
 */
export default function StudyBot({ profile }) {
  const [tab, setTab] = useState('chat');

  return (
    <div className="p-6 max-w-4xl mx-auto space-y-4">
      <h1 className="text-2xl font-bold text-teal-900">AI Study Companion</h1>

      <div className="flex gap-2 border-b border-slate-200">
        <TabButton active={tab === 'chat'} onClick={() => setTab('chat')}>Chat</TabButton>
        <TabButton active={tab === 'notes'} onClick={() => setTab('notes')}>Notes → Flowchart & Quiz</TabButton>
      </div>

      {tab === 'chat' ? <ChatPanel profile={profile} /> : <NotesPanel profile={profile} />}
    </div>
  );
}

function TabButton({ active, onClick, children }) {
  return (
    <button
      onClick={onClick}
      className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition ${
        active ? 'border-teal-600 text-teal-700' : 'border-transparent text-slate-400 hover:text-slate-600'
      }`}
    >
      {children}
    </button>
  );
}

// ---------------------------------------------------------------------
// Chat panel
// ---------------------------------------------------------------------
function ChatPanel({ profile }) {
  const [messages, setMessages] = useState([
    { role: 'assistant', content: "Hi! I'm your Ayush StudyBot. Paste some notes or ask me anything." },
  ]);
  const [input, setInput] = useState('');
  const [sending, setSending] = useState(false);
  const scrollRef = useRef(null);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' });
  }, [messages]);

  async function send() {
    if (!input.trim() || sending) return;
    const userMsg = { role: 'user', content: input };
    const nextMessages = [...messages, userMsg];
    setMessages(nextMessages);
    setInput('');
    setSending(true);
    try {
      const data = await apiRequest(`/api/students/${profile.id}/study-bot/chat`, {
        method: 'POST',
        body: { message: userMsg.content, history: nextMessages.slice(0, -1) },
      });
      setMessages((prev) => [...prev, { role: 'assistant', content: data.reply }]);
    } catch (e) {
      setMessages((prev) => [...prev, { role: 'assistant', content: `⚠️ ${e.message}` }]);
    } finally {
      setSending(false);
    }
  }

  return (
    <div className="bg-white rounded-2xl shadow flex flex-col h-[520px]">
      <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 space-y-3">
        {messages.map((m, i) => (
          <div key={i} className={`flex ${m.role === 'user' ? 'justify-end' : 'justify-start'}`}>
            <div
              className={`max-w-[75%] px-4 py-2 rounded-2xl text-sm whitespace-pre-wrap ${
                m.role === 'user' ? 'bg-teal-700 text-white rounded-br-sm' : 'bg-slate-100 text-slate-800 rounded-bl-sm'
              }`}
            >
              {m.content}
            </div>
          </div>
        ))}
        {sending && <div className="text-xs text-slate-400">StudyBot is typing…</div>}
      </div>
      <div className="border-t border-slate-100 p-3 flex gap-2">
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && send()}
          placeholder="Ask a question..."
          className="flex-1 rounded-xl border border-slate-200 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-teal-500"
        />
        <button
          onClick={send}
          disabled={sending}
          className="bg-teal-700 hover:bg-teal-800 disabled:opacity-50 text-white px-4 py-2 rounded-xl text-sm font-medium"
        >
          Send
        </button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------
// Notes -> Flowchart + Quiz panel
// ---------------------------------------------------------------------
function NotesPanel({ profile }) {
  const [title, setTitle] = useState('');
  const [notes, setNotes] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [result, setResult] = useState(null);

  async function handleGenerate() {
    if (!notes.trim()) {
      setError('Paste some notes first.');
      return;
    }
    setLoading(true);
    setError(null);
    setResult(null);
    try {
      const data = await apiRequest(`/api/students/${profile.id}/study-bot/notes`, {
        method: 'POST',
        body: { title: title || 'Untitled Notes', raw_notes: notes },
      });
      setResult(data);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="space-y-6">
      <div className="bg-white rounded-2xl shadow p-6 space-y-3">
        <input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="Note title (e.g. 'Panchakarma - Vamana procedure')"
          className="w-full rounded-xl border border-slate-200 px-3 py-2 text-sm"
        />
        <textarea
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          rows={8}
          placeholder="Paste your academic notes here..."
          className="w-full rounded-xl border border-slate-200 p-3 text-sm focus:outline-none focus:ring-2 focus:ring-teal-500"
        />
        <button
          onClick={handleGenerate}
          disabled={loading}
          className="bg-teal-700 hover:bg-teal-800 disabled:opacity-50 text-white font-medium px-5 py-2 rounded-xl transition"
        >
          {loading ? 'Generating…' : 'Generate Flowchart & Quiz'}
        </button>
        {error && <p className="text-red-600 text-sm">{error}</p>}
      </div>

      {result && (
        <>
          <MermaidRenderer chart={result.mermaid_syntax} />
          <QuizBlock quiz={result.quiz} />
        </>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------
// Mermaid renderer
// ---------------------------------------------------------------------
function MermaidRenderer({ chart }) {
  const containerRef = useRef(null);
  const [svg, setSvg] = useState('');
  const [renderError, setRenderError] = useState(null);

  useEffect(() => {
    if (!chart) return;
    let cancelled = false;
    const id = `mermaid-${Date.now()}`;

    mermaid
      .render(id, chart)
      .then(({ svg }) => {
        if (!cancelled) setSvg(svg);
      })
      .catch((err) => {
        if (!cancelled) setRenderError(err.message || 'Failed to render diagram');
      });

    return () => {
      cancelled = true;
    };
  }, [chart]);

  return (
    <div className="bg-white rounded-2xl shadow p-6">
      <h3 className="font-semibold text-slate-700 mb-3">Visual Flowchart</h3>
      {renderError && (
        <p className="text-sm text-red-600">
          Could not render diagram ({renderError}). Raw syntax:
          <pre className="bg-slate-50 p-2 rounded mt-2 text-xs overflow-x-auto">{chart}</pre>
        </p>
      )}
      {!renderError && (
        <div ref={containerRef} className="overflow-x-auto" dangerouslySetInnerHTML={{ __html: svg }} />
      )}
    </div>
  );
}

// ---------------------------------------------------------------------
// Quiz block
// ---------------------------------------------------------------------
function QuizBlock({ quiz = [] }) {
  const [answers, setAnswers] = useState({});
  const [submitted, setSubmitted] = useState(false);

  function selectAnswer(qIdx, optIdx) {
    if (submitted) return;
    setAnswers((prev) => ({ ...prev, [qIdx]: optIdx }));
  }

  const score = quiz.reduce((acc, q, i) => acc + (answers[i] === q.correct_index ? 1 : 0), 0);

  return (
    <div className="bg-white rounded-2xl shadow p-6">
      <div className="flex justify-between items-center mb-4">
        <h3 className="font-semibold text-slate-700">Quick Quiz</h3>
        {submitted && (
          <span className="text-sm font-medium text-teal-700">
            Score: {score}/{quiz.length}
          </span>
        )}
      </div>

      <div className="space-y-5">
        {quiz.map((q, qIdx) => (
          <div key={qIdx}>
            <p className="text-sm font-medium text-slate-800 mb-2">
              {qIdx + 1}. {q.question}
            </p>
            <div className="grid gap-2">
              {q.options.map((opt, optIdx) => {
                const isSelected = answers[qIdx] === optIdx;
                const isCorrect = submitted && optIdx === q.correct_index;
                const isWrongSelected = submitted && isSelected && optIdx !== q.correct_index;
                return (
                  <button
                    key={optIdx}
                    onClick={() => selectAnswer(qIdx, optIdx)}
                    className={`text-left text-sm px-3 py-2 rounded-xl border transition ${
                      isCorrect
                        ? 'bg-emerald-50 border-emerald-400 text-emerald-800'
                        : isWrongSelected
                        ? 'bg-red-50 border-red-400 text-red-700'
                        : isSelected
                        ? 'bg-teal-50 border-teal-400'
                        : 'border-slate-200 hover:bg-slate-50'
                    }`}
                  >
                    {opt}
                  </button>
                );
              })}
            </div>
            {submitted && (
              <p className="text-xs text-slate-500 mt-1 italic">{q.explanation}</p>
            )}
          </div>
        ))}
      </div>

      {!submitted && quiz.length > 0 && (
        <button
          onClick={() => setSubmitted(true)}
          className="mt-5 bg-teal-700 hover:bg-teal-800 text-white font-medium px-5 py-2 rounded-xl text-sm"
        >
          Submit Answers
        </button>
      )}
    </div>
  );
}
