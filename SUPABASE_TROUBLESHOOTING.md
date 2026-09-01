# Supabase Setup Troubleshooting Guide

## Issue
The app shows "Database error querying schema" when trying to sign in. This is caused by circular dependencies in the RLS (Row Level Security) policies.

## Solution - Follow These Steps:

### STEP 1: Verify Tables Exist
1. Go to https://app.supabase.com
2. Log into your project
3. Go to **SQL Editor** 
4. Run this query:
```sql
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' 
ORDER BY table_name;
```
5. You should see tables like: `profiles`, `skills`, `jobs`, `applications`, `notes`, etc.

**If no tables appear**, the schema didn't apply. Go back and re-run the entire `schema.sql` file.

### STEP 2: Verify Demo Users Exist
1. Still in SQL Editor, run:
```sql
SELECT id, email, raw_user_meta_data FROM auth.users LIMIT 5;
```
2. You should see users like `ansh@student.ayush.demo`, etc.

**If no users appear**, re-run just the seed data section (11.1 and 11.2) of schema.sql.

### STEP 3: FIX THE RLS POLICIES (CRITICAL)
1. In SQL Editor, open the file: `supabase/fix_rls.sql` from your project
2. Copy the entire contents
3. Paste into a new SQL Query in Supabase
4. Click **Run**

This removes the circular RLS dependencies and applies simplified policies.

### STEP 4: Test Authentication
1. Go back to http://localhost:5173
2. Try signing in with demo account:
   - Email: `ansh@student.ayush.demo`
   - Password: `Password123!`

3. OR try creating a new account with Sign Up

### If it Still Doesn't Work:
Run this diagnostic query to check for RLS policy errors:
```sql
-- Check profiles table RLS
SELECT * FROM pg_policies WHERE tablename = 'profiles';

-- Test direct profile read  
SELECT id, full_name, role FROM public.profiles LIMIT 1;
```

## Why This Happened
The original schema used a `current_role()` function that tried to query the `profiles` table from within an RLS policy. This created a circular dependency:
- RLS policy calls `current_role()`
- `current_role()` queries `profiles` table  
- But `profiles` table has RLS enabled
- This causes the error

The fix removes the circular dependency by using simpler, direct role checks.

---

**After fixing, the app will work and you can deploy to Render + Vercel!**
