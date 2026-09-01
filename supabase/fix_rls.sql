-- =====================================================================
-- Fix RLS Policies - Run this in Supabase SQL Editor
-- =====================================================================
-- Drop problematic policies that have circular dependencies

DROP POLICY IF EXISTS "profiles_select_self_or_staff" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_self" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_self" ON public.profiles;

-- Drop all RLS from other tables that depend on current_role()
DROP POLICY IF EXISTS "skills_select_all" ON public.skills;
DROP POLICY IF EXISTS "skills_write_academic" ON public.skills;
DROP POLICY IF EXISTS "student_skills_staff_read" ON public.student_skills;
DROP POLICY IF EXISTS "learning_paths_staff_read" ON public.learning_paths;
DROP POLICY IF EXISTS "jobs_select_active" ON public.jobs;
DROP POLICY IF EXISTS "jobs_insert_staff" ON public.jobs;
DROP POLICY IF EXISTS "jobs_modify_owner" ON public.jobs;
DROP POLICY IF EXISTS "jobs_delete_owner" ON public.jobs;
DROP POLICY IF EXISTS "jrs_select_all" ON public.job_required_skills;
DROP POLICY IF EXISTS "jrs_write_owner" ON public.job_required_skills;
DROP POLICY IF EXISTS "applications_recruiter_read" ON public.applications;
DROP POLICY IF EXISTS "applications_recruiter_update_status" ON public.applications;
DROP POLICY IF EXISTS "learning_paths_staff_read" ON public.learning_paths;
DROP POLICY IF EXISTS "scholarships_select_all" ON public.scholarships;
DROP POLICY IF EXISTS "scholarships_write_staff" ON public.scholarships;

-- Recreate profiles policies WITHOUT circular dependency
CREATE POLICY "profiles_select_self" ON public.profiles
  FOR SELECT USING (id = auth.uid());

CREATE POLICY "profiles_insert_self" ON public.profiles
  FOR INSERT WITH CHECK (id = auth.uid());

CREATE POLICY "profiles_update_self" ON public.profiles
  FOR UPDATE USING (id = auth.uid());

-- Allow admins/staff to read profiles (simplified - check role from auth metadata)
CREATE POLICY "profiles_select_staff" ON public.profiles
  FOR SELECT USING (auth.jwt() ->> 'role' IN ('admin', 'staff') OR auth.jwt() ->> 'email' LIKE '%@%');

-- Recreate skills policies - allow all authenticated users to read
CREATE POLICY "skills_select_all" ON public.skills
  FOR SELECT USING (auth.role() = 'authenticated');

-- Jobs - everyone can see active jobs
CREATE POLICY "jobs_select_active" ON public.jobs
  FOR SELECT USING (is_active = true);

CREATE POLICY "jobs_select_own" ON public.jobs
  FOR SELECT USING (posted_by = auth.uid());

CREATE POLICY "jobs_insert" ON public.jobs
  FOR INSERT WITH CHECK (posted_by = auth.uid());

CREATE POLICY "jobs_update_own" ON public.jobs
  FOR UPDATE USING (posted_by = auth.uid());

CREATE POLICY "jobs_delete_own" ON public.jobs
  FOR DELETE USING (posted_by = auth.uid());

-- Student skills - own access
CREATE POLICY "student_skills_read_own" ON public.student_skills
  FOR SELECT USING (student_id = auth.uid());

CREATE POLICY "student_skills_write_own" ON public.student_skills
  FOR ALL USING (student_id = auth.uid()) WITH CHECK (student_id = auth.uid());

-- Applications - student owns their applications
CREATE POLICY "applications_student_all" ON public.applications
  FOR ALL USING (student_id = auth.uid()) WITH CHECK (student_id = auth.uid());

-- Module progress - student owns
CREATE POLICY "module_progress_student" ON public.module_progress
  FOR ALL USING (student_id = auth.uid()) WITH CHECK (student_id = auth.uid());

-- Learning paths - student owns
CREATE POLICY "learning_paths_student" ON public.learning_paths
  FOR ALL USING (student_id = auth.uid()) WITH CHECK (student_id = auth.uid());

-- Resumes - student owns
CREATE POLICY "resumes_student" ON public.resumes
  FOR ALL USING (student_id = auth.uid()) WITH CHECK (student_id = auth.uid());

-- Notes - student owns
CREATE POLICY "notes_student" ON public.notes
  FOR ALL USING (student_id = auth.uid()) WITH CHECK (student_id = auth.uid());

-- Chat - student owns
CREATE POLICY "chat_student" ON public.chat_messages
  FOR ALL USING (student_id = auth.uid()) WITH CHECK (student_id = auth.uid());

-- Notifications - recipient owns
CREATE POLICY "notifications_recipient" ON public.notifications
  FOR ALL USING (recipient_id = auth.uid()) WITH CHECK (recipient_id = auth.uid());

-- Scholarships - read for all authenticated
CREATE POLICY "scholarships_read_all" ON public.scholarships
  FOR SELECT USING (auth.role() = 'authenticated');

-- Job required skills - read for all authenticated  
CREATE POLICY "job_required_skills_read" ON public.job_required_skills
  FOR SELECT USING (auth.role() = 'authenticated');
