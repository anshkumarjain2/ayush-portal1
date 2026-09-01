# Deployment Checklist — Ayush Academia-Industry Collaboration Portal

## 1. Supabase (do this first)
1. Create a new Supabase project.
2. Open the SQL editor and run `supabase/schema.sql` in full (it creates
   tables, RLS policies, the `handle_new_user` trigger, and seed data).
3. Note down, from **Project Settings → API**:
   - `Project URL` → used as `SUPABASE_URL` / `VITE_SUPABASE_URL`
   - `anon public` key → used as `VITE_SUPABASE_ANON_KEY`
   - `service_role` key → used as `SUPABASE_SERVICE_ROLE_KEY` (backend only, **never** ship to frontend)
4. In **Authentication → Providers**, enable Email/Password (and any others you want, e.g. Google).
5. The demo seed users (ansh@student.ayush.demo, etc., password `Password123!`)
   are inserted directly into `auth.users` for convenience — in a real
   deploy, prefer signing up through the app so Supabase Auth manages
   password hashing end-to-end. If direct insert fails due to Supabase
   Auth schema restrictions on your project tier, sign up each demo user
   via the app's normal signup flow instead and skip section 11.1 of the SQL file.

## 2. Google Gemini API
1. Get an API key from Google AI Studio.
2. This becomes `GEMINI_API_KEY` on the backend only.

## 3. Backend — Render
Deploy `backend/` as a Web Service using `render.yaml` (Render will
detect it automatically via "New → Blueprint", or configure manually):

- **Build Command:** `pip install -r requirements.txt`
- **Start Command:** `uvicorn main:app --host 0.0.0.0 --port $PORT`

### Required environment variables (Render → Environment):
| Variable | Description |
|---|---|
| `SUPABASE_URL` | Your Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase service-role key (secret) |
| `GEMINI_API_KEY` | Google Gemini API key |
| `GEMINI_MODEL` | e.g. `gemini-2.5-flash` (optional, has a default) |
| `CRON_SECRET` | Random shared secret to protect `/api/cron/scholarship-alerts` |

After deploying, copy the Render service URL (e.g.
`https://ayush-portal-api.onrender.com`) — you'll need it for the
frontend's `VITE_API_BASE_URL`, and update `ALLOWED_ORIGINS` /
`allow_origin_regex` in `main.py` with your actual Vercel domain(s).

### Scheduled scholarship alerts
Either use the `cron` service block already in `render.yaml`, or set up
an external scheduler (GitHub Actions `schedule:`, cron-job.org, etc.)
to `POST` to `/api/cron/scholarship-alerts` daily with header
`X-Cron-Secret: <CRON_SECRET>`.

## 4. Frontend — Vercel
Deploy `frontend/` as a Vite project.

- **Framework Preset:** Vite
- **Build Command:** `npm run build`
- **Output Directory:** `dist`

### Required environment variables (Vercel → Project Settings → Environment Variables):
| Variable | Description |
|---|---|
| `VITE_SUPABASE_URL` | Same Supabase project URL as above |
| `VITE_SUPABASE_ANON_KEY` | Supabase anon/public key |
| `VITE_API_BASE_URL` | Your deployed Render backend URL, no trailing slash |

### Frontend dependencies to install before building
```bash
npm install @supabase/supabase-js recharts mermaid
```
(Tailwind should already be configured via your Vite + Tailwind setup;
if not: `npm install -D tailwindcss postcss autoprefixer` and run
`npx tailwindcss init -p`.)

## 5. Post-deploy sanity checks
- [ ] Visit `https://<render-app>.onrender.com/` → should return `{"status": "ok", ...}`
- [ ] Sign in on the deployed frontend with a seeded demo student
      (`ansh@student.ayush.demo` / `Password123!`)
- [ ] Confirm the Dashboard loads matched opportunities without CORS errors
- [ ] Run a resume gap analysis on SkillMapping and confirm Gemini returns structured JSON
- [ ] Paste notes into StudyBot and confirm the Mermaid diagram renders and quiz is interactive
- [ ] Manually hit `/api/cron/scholarship-alerts` with the correct `X-Cron-Secret` header and confirm notifications are created

## 6. Security notes
- Never expose `SUPABASE_SERVICE_ROLE_KEY` or `GEMINI_API_KEY` to the frontend — they live only in Render's environment.
- RLS policies in `schema.sql` are the real access-control boundary; the FastAPI service-role client bypasses RLS deliberately for cross-table logic (matching, unlocking, analytics), so keep that key secret.
- Rotate `CRON_SECRET` and API keys before/after any public hackathon demo where the repo might be shared.
