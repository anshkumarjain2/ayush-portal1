# Deployment Guide - Ayush Portal

## Quick Start Checklist

- [ ] Backend deployed to Render
- [ ] Frontend deployed to Vercel  
- [ ] Database schema applied to Supabase
- [ ] Environment variables configured
- [ ] All services tested and working

---

## 1. Apply Database Schema to Supabase ⚠️ **DO THIS FIRST**

### Steps:
1. Go to: https://app.supabase.com → Select project `yfpgkrjxlykutlkhnqyj`
2. Click **SQL Editor** → **New Query**
3. Open your local file: `supabase/schema.sql`
4. Copy **ALL** contents
5. Paste into Supabase SQL Editor
6. Click **Run** button
7. Wait for completion (no errors should appear)

**What it does:**
- Creates all 14 tables with relationships
- Sets up Row-Level Security (RLS) policies (simplified, no circular dependencies)
- Populates seed data (9 demo users, 10 skills, 6 jobs, etc.)
- Creates auto-profile trigger for new signups

**Demo Credentials (after schema applied):**
- Email: `ansh@student.ayush.demo`
- Password: `Password123!`

---

## 2. Deploy Backend to Render 🚀

### Option A: Using Render CLI (Recommended)

```bash
# Install Render CLI
npm install -g @render-com/cli

# Deploy from your project root
cd backend
render deploy
```

### Option B: Manual Deploy via Dashboard

1. Go to: https://dashboard.render.com
2. Click **New** → **Web Service**
3. Connect GitHub repo: `anshkumarjain2/ayush-portal1`
4. Configure:
   - **Name:** `ayush-portal-api`
   - **Environment:** `Python 3.11`
   - **Root Directory:** `backend`
   - **Build Command:** `pip install -r requirements.txt`
   - **Start Command:** `uvicorn main:app --host 0.0.0.0 --port $PORT`
   - **Plan:** Free (or Starter if you need custom domain)

5. **Add Environment Variables** (click "Add from .env"):
   ```
   SUPABASE_URL = https://yfpgkrjxlykutlkhnqyj.supabase.co
   SUPABASE_SERVICE_ROLE_KEY = [Your Supabase Service Role Key]
   GEMINI_API_KEY = [Your Google Gemini API Key]
   GEMINI_MODEL = gemini-2.5-flash
   CRON_SECRET = [Generate a random secret for cron jobs]
   ```

6. Click **Create Web Service**
7. Wait 3-5 minutes for deployment to complete

**Get Environment Variables:**
- `SUPABASE_URL`: https://app.supabase.com → Project Settings → API
- `SUPABASE_SERVICE_ROLE_KEY`: https://app.supabase.com → Project Settings → API → Service Role (copy the key)
- `GEMINI_API_KEY`: https://console.cloud.google.com → Create API key

**Backend URL after deployment:** https://ayush-portal-api.onrender.com

---

## 3. Deploy Frontend to Vercel ✨

### Option A: Using Vercel CLI (Recommended)

```bash
# Install Vercel CLI
npm install -g vercel

# Deploy from project root
cd frontend
vercel
```

### Option B: Manual Deploy via Dashboard

1. Go to: https://vercel.com
2. Click **Add New** → **Project**
3. Import GitHub repo: `anshkumarjain2/ayush-portal1`
4. Configure:
   - **Framework:** Vite
   - **Root Directory:** `frontend`
   - **Build Command:** `npm run build`
   - **Output Directory:** `dist`

5. **Add Environment Variables:**
   ```
   VITE_SUPABASE_URL = https://yfpgkrjxlykutlkhnqyj.supabase.co
   VITE_SUPABASE_ANON_KEY = [Your Supabase Anon Key]
   VITE_API_BASE_URL = https://ayush-portal-api.onrender.com
   ```

6. Click **Deploy**
7. Wait 2-3 minutes for deployment to complete

**Get Supabase Anon Key:**
- https://app.supabase.com → Project Settings → API → Anon Key

**Frontend URL after deployment:** https://ayush-portal1.vercel.app

---

## 4. Post-Deployment Testing 🧪

### Test Backend Health
```bash
curl https://ayush-portal-api.onrender.com/
# Should return: {"status": "ok"}
```

### Test Frontend Loading
1. Visit: https://ayush-portal1.vercel.app
2. Should see login form

### Test Login Flow
1. Enter demo credentials:
   - Email: `ansh@student.ayush.demo`
   - Password: `Password123!`
2. Should redirect to Dashboard
3. Should see jobs and opportunities

### Test API Integration
1. Open browser DevTools (F12)
2. Go to Network tab
3. Try skill mapping or study bot features
4. Check if API calls return 200 status

---

## 5. Troubleshooting

### Backend returns 404
- [ ] Check Render dashboard for deployment status
- [ ] Review build logs for errors
- [ ] Verify environment variables are set
- [ ] Ensure requirements.txt installed correctly

### Frontend shows blank page
- [ ] Check Vercel deployment logs
- [ ] Verify environment variables in Vercel dashboard
- [ ] Check browser console for errors (F12)
- [ ] Clear cache and reload

### Login fails with "Database error"
- [ ] Verify schema.sql was applied to Supabase
- [ ] Check Supabase SQL Editor for any error messages
- [ ] Verify SUPABASE_URL and SUPABASE_ANON_KEY are correct
- [ ] Check Supabase authentication logs

### API calls fail with CORS error
- [ ] Backend CORS is configured for Vercel domains
- [ ] Check backend console logs for CORS issues
- [ ] Verify API_BASE_URL in frontend env matches backend URL

---

## 6. Monitoring & Logs

### View Backend Logs
1. Go to: https://dashboard.render.com
2. Click on `ayush-portal-api` service
3. Click **Logs** tab

### View Frontend Logs
1. Go to: https://vercel.com/dashboard
2. Click on `ayush-portal1` project
3. Click **Deployments** → Select deployment → **Logs**

### View Database Logs
1. Go to: https://app.supabase.com
2. Click **Database** → **PostgreSQL Logs**

---

## 7. Environment Variables Summary

| Variable | Backend | Frontend | Where to Get |
|----------|---------|----------|--------------|
| `SUPABASE_URL` | ✓ | ✓ | Supabase Project Settings → API |
| `SUPABASE_ANON_KEY` | | ✓ | Supabase Project Settings → API |
| `SUPABASE_SERVICE_ROLE_KEY` | ✓ | | Supabase Project Settings → API |
| `GEMINI_API_KEY` | ✓ | | Google Cloud Console |
| `GEMINI_MODEL` | ✓ | | gemini-2.5-flash |
| `VITE_API_BASE_URL` | | ✓ | https://ayush-portal-api.onrender.com |
| `CRON_SECRET` | ✓ | | Generate random string |

---

## 8. Production Checklist

- [ ] Schema applied to Supabase ✓
- [ ] Environment variables configured
- [ ] Backend deployed and health check passes
- [ ] Frontend deployed and loads without errors
- [ ] Login works with demo credentials
- [ ] Can view dashboard and jobs
- [ ] API endpoints return data
- [ ] All features tested (skill mapping, study bot, etc.)
- [ ] No console errors in browser
- [ ] No errors in backend logs
- [ ] Database queries working
- [ ] CORS configured correctly

---

## 9. Rollback Procedures

### Rollback Backend
```bash
# On Render dashboard, click "Deploy" and select previous version
# Or push a fix to GitHub and auto-deploy will trigger
```

### Rollback Frontend
```bash
# On Vercel dashboard, click "Deployments" and select previous version
# Or push a fix to GitHub and auto-deploy will trigger
```

### Rollback Database
```sql
-- Do NOT delete the current schema
-- Instead, keep backups and carefully migrate changes
-- Run schema_clean.sql in a separate database first to test
```

---

**Status:** Ready for production 🎉

**Next Steps:**
1. ✅ Push code to GitHub (already done)
2. ⏳ Apply schema.sql to Supabase
3. ⏳ Deploy backend to Render
4. ⏳ Deploy frontend to Vercel
5. ⏳ Run tests and verify everything works

Questions? Check logs in Render/Vercel/Supabase dashboards!
