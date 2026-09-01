# From VS Code to a Live MVP Link — Full Step-by-Step Guide

This walks you through everything: opening the project in VS Code,
running it locally, and deploying it so you have a real, shareable
URL for your hackathon demo.

**Total time:** ~45–60 minutes the first time.

---

## Part 0 — Accounts & tools you need (do this first)

Create free accounts on:
1. **Supabase** — https://supabase.com
2. **Render** — https://render.com
3. **Vercel** — https://vercel.com
4. **Google AI Studio** (for a Gemini API key) — https://aistudio.google.com/app/apikey
5. **GitHub** — https://github.com (Render and Vercel both deploy from a Git repo)

Install on your machine:
- **VS Code** — https://code.visualstudio.com
- **Node.js LTS** (v18 or v20) — https://nodejs.org — this gives you `node` and `npm`
- **Python 3.11+** — https://python.org
- **Git** — https://git-scm.com

Verify installs in a terminal:
```bash
node -v
npm -v
python3 --version
git --version
```

---

## Part 1 — Open the project in VS Code

1. Unzip `ayush-portal.zip` somewhere on your machine, e.g. `~/projects/ayush-portal`.
2. Open VS Code → **File → Open Folder** → select the `ayush-portal` folder.
3. Install these VS Code extensions (Extensions panel, `Ctrl+Shift+X` / `Cmd+Shift+X`):
   - **Python** (Microsoft)
   - **ES7+ React/Redux/React-Native snippets** (optional, nice-to-have)
   - **Tailwind CSS IntelliSense** (optional)
4. Open the integrated terminal: **Terminal → New Terminal** (`` Ctrl+` ``). You'll run all commands below from here. VS Code lets you split terminals — keep one for the backend and one for the frontend.

---

## Part 2 — Set up Supabase (the database)

1. In the Supabase dashboard, click **New Project**. Choose a name, a strong database password (save it somewhere), and a region close to you.
2. Once it's provisioned, go to **SQL Editor → New query**.
3. Open `supabase/schema.sql` in VS Code, copy the **entire file**, paste it into the Supabase SQL editor, and click **Run**.
   - This creates all tables, RLS policies, and seed data (Ansh, Akshat, Tanmay, Sumit, Bharat, Hardik, two recruiters, one academician).
   - If the `auth.users` insert section (11.1) errors out on your Supabase tier (some managed instances restrict direct writes to `auth.users`), skip that block and instead sign up each demo user later through the app's normal Sign Up screen — then re-run just the "insert into public.profiles" and downstream seed sections.
4. Go to **Authentication → Providers** and make sure **Email** is enabled (it is by default).
5. Go to **Authentication → Settings** and, for a smooth demo, temporarily **disable "Confirm email"** so test signups don't need to click a confirmation link. (Re-enable for a real production launch.)
6. Go to **Project Settings → API** and copy these three values somewhere safe — you'll need them shortly:
   - **Project URL**
   - **anon public** key
   - **service_role** key (keep this one secret — it bypasses all security rules)

---

## Part 3 — Get your Gemini API key

1. Go to https://aistudio.google.com/app/apikey.
2. Click **Create API key**, copy it.

---

## Part 4 — Run the backend locally (VS Code terminal)

**Yes — use a virtual environment for local development.** It keeps this project's Python packages isolated from anything else on your machine and matches how most tutorials/CI expect a FastAPI project to be run. (More on deployment further down — Render does **not** need you to manage a venv yourself.)

```bash
cd backend

# create the virtual environment
python3 -m venv venv

# activate it
source venv/bin/activate        # macOS/Linux
venv\Scripts\activate           # Windows (Command Prompt)
venv\Scripts\Activate.ps1       # Windows (PowerShell)
```

You'll see `(venv)` appear at the start of your terminal prompt once it's active. In VS Code, once you select this venv as your Python interpreter (bottom-right corner → click the Python version → pick `./backend/venv/...`), the editor will also use it for linting/autocomplete.

```bash
# install dependencies (still inside backend/, venv active)
pip install -r requirements.txt
```

Now create your local secrets file:
```bash
cp .env.example .env
```
Open `backend/.env` in VS Code and fill in the real values:
```
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
GEMINI_API_KEY=your-gemini-key
GEMINI_MODEL=gemini-2.5-flash
CRON_SECRET=any-random-string-you-make-up
```

Run the server:
```bash
uvicorn main:app --reload
```

You should see `Uvicorn running on http://127.0.0.1:8000`. Test it by visiting **http://localhost:8000** in a browser — you should get `{"status": "ok", ...}`. Interactive API docs are auto-generated at **http://localhost:8000/docs**.

Leave this terminal running.

---

## Part 5 — Run the frontend locally (second VS Code terminal)

Open a **new** terminal (don't close the backend one).

```bash
cd frontend
npm install
```

Create your local env file:
```bash
cp .env.example .env.local
```
Fill in `frontend/.env.local`:
```
VITE_SUPABASE_URL=https://your-project-ref.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key
VITE_API_BASE_URL=http://localhost:8000
```

Start the dev server:
```bash
npm run dev
```

Open the printed URL (usually **http://localhost:5173**). You should see the login screen. Sign in with a seeded demo account:
- Email: `ansh@student.ayush.demo`
- Password: `Password123!`

(If you skipped the direct `auth.users` seed insert in Part 2, use **Sign Up** instead to create a fresh account, then in Supabase's Table Editor manually set that user's `role` in the `profiles` table if you didn't pick "student".)

At this point your MVP works fully on your machine: dashboard, resume gap analysis (calls Gemini), and the study bot with Mermaid diagrams and quizzes.

> **Node.js equivalent of a "virtual environment"?** Node doesn't need one — `npm install` already installs packages into a project-local `node_modules/` folder, so there's no global pollution to worry about. Nothing extra to set up here.

---

## Part 6 — Push the project to GitHub

Both Render and Vercel deploy from a Git repository.

```bash
cd ayush-portal          # the root folder, not backend/ or frontend/
git init
git add .
git commit -m "Initial commit: Ayush Academia-Industry Portal MVP"
```

Create a new empty repo on GitHub (no README/gitignore — you already have one), then:
```bash
git remote add origin https://github.com/YOUR-USERNAME/ayush-portal.git
git branch -M main
git push -u origin main
```

The `.gitignore` already excludes `node_modules/`, `venv/`, and your `.env` files, so secrets won't be pushed.

---

## Part 7 — Deploy the backend to Render

1. In the Render dashboard, click **New → Web Service**.
2. Connect your GitHub account and select the `ayush-portal` repo.
3. Render will ask for a **Root Directory** — set it to `backend`.
4. Settings:
   - **Runtime:** Python 3
   - **Build Command:** `pip install -r requirements.txt`
   - **Start Command:** `uvicorn main:app --host 0.0.0.0 --port $PORT`
   - **Instance Type:** Free (fine for a hackathon demo)
5. Under **Environment Variables**, add the same keys from `backend/.env`:
   | Key | Value |
   |---|---|
   | `SUPABASE_URL` | your Supabase project URL |
   | `SUPABASE_SERVICE_ROLE_KEY` | your service-role key |
   | `GEMINI_API_KEY` | your Gemini key |
   | `GEMINI_MODEL` | `gemini-2.5-flash` |
   | `CRON_SECRET` | your random secret |
6. Click **Create Web Service**. Render will build and deploy — this takes 2–5 minutes on the free tier.
7. Once live, copy the URL Render gives you, e.g. `https://ayush-portal-api.onrender.com`. Visit it — you should see `{"status": "ok", ...}` again, now from the internet.

> **About `render.yaml`:** if you prefer, instead of manually clicking through the UI you can use **New → Blueprint** and point it at the repo — Render will read `backend/render.yaml` and configure the service (plus the optional cron job) automatically. Manual setup as above is more beginner-friendly for a first deploy.

> Free-tier Render web services "sleep" after 15 minutes of no traffic and take ~30–60 seconds to wake up on the next request — expected behavior for a free demo, not a bug.

---

## Part 8 — Deploy the frontend to Vercel

1. In the Vercel dashboard, click **Add New → Project**.
2. Import the same `ayush-portal` GitHub repo.
3. Vercel will ask to configure the project:
   - **Root Directory:** click "Edit" and set it to `frontend`
   - **Framework Preset:** Vite (should auto-detect)
   - **Build Command:** `npm run build`
   - **Output Directory:** `dist`
4. Under **Environment Variables**, add:
   | Key | Value |
   |---|---|
   | `VITE_SUPABASE_URL` | your Supabase project URL |
   | `VITE_SUPABASE_ANON_KEY` | your Supabase anon key |
   | `VITE_API_BASE_URL` | your Render backend URL from Part 7, **no trailing slash** |
5. Click **Deploy**. Takes about a minute.
6. Vercel gives you a live URL like `https://ayush-portal-yourname.vercel.app` — **this is your shareable MVP link.**

---

## Part 9 — Connect the two (fix CORS)

The backend's `main.py` only accepts requests from specific frontend origins. Update it with your real Vercel URL:

1. In VS Code, open `backend/main.py` and find:
   ```python
   ALLOWED_ORIGINS = [
       "http://localhost:5173",
       "https://ayush-portal.vercel.app",
       "https://ayush-portal-*.vercel.app",
   ]
   ...
   allow_origin_regex=r"https://ayush-portal.*\.vercel\.app",
   ```
2. Replace the placeholder URLs with your actual Vercel domain from Part 8 (both the exact production URL and, if it differs, adjust the regex to match your project's preview-URL pattern, e.g. `your-project-name-*.vercel.app`).
3. Commit and push:
   ```bash
   git add backend/main.py
   git commit -m "Update CORS origins for deployed frontend"
   git push
   ```
4. Render auto-redeploys on every push to `main` (this is on by default — "Auto-Deploy").

---

## Part 10 — Final test on the live link

1. Open your Vercel URL in a browser.
2. Sign in with `ansh@student.ayush.demo` / `Password123!`.
3. Check the Dashboard loads matched opportunities (no CORS errors in the browser console — open DevTools → Console to confirm).
4. Go to Skill Mapping, paste some resume text, run gap analysis — confirm Gemini returns a structured result.
5. Go to Study Bot, paste some notes, confirm the Mermaid flowchart renders and the quiz is clickable.

If something fails, check in this order: browser console (CORS/network errors) → Render logs (backend crashes, missing env vars) → Supabase logs (RLS rejections) → Vercel build logs (missing env vars at build time).

---

## Virtual environments — direct answer

| Where | Use a virtual environment? |
|---|---|
| **Local backend development (your laptop)** | **Yes.** Create one with `python3 -m venv venv` inside `backend/` and activate it before running `pip install` / `uvicorn`. This is standard practice and keeps this project's dependencies from clashing with other Python projects on your machine. |
| **Render (backend deployment)** | **You don't manage it yourself.** Render builds your service inside its own fresh, isolated container for every deploy — conceptually the same idea as a venv, but handled by the platform. You never run `venv` commands in Render's build/start commands; `pip install -r requirements.txt` inside Render's container is enough. |
| **Frontend (local or Vercel)** | **N/A — no Python venv concept applies.** `npm install` already isolates dependencies per-project into `node_modules/`, and Vercel builds in its own clean container too. |

So: venv locally for the backend, nowhere else needed.

---

## Optional next step — the scholarship cron alert

`backend/render.yaml` includes an optional Render Cron Job that hits
`/api/cron/scholarship-alerts` daily. Cron Jobs are a separate Render
service type and may require a paid plan depending on your account/region.
For a hackathon demo, it's enough to trigger it manually once to show
judges it works:
```bash
curl -X POST https://your-render-url.onrender.com/api/cron/scholarship-alerts \
  -H "X-Cron-Secret: your-cron-secret"
```
