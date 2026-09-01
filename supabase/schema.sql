-- =====================================================================
-- Ministry of Ayush — Academia-Industry Collaboration Portal
-- Clean Schema without circular RLS dependencies
-- =====================================================================
-- Run this in the Supabase SQL editor

-- Drop existing objects if they exist
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.current_role();

-- Drop existing tables
DROP TABLE IF EXISTS public.notifications CASCADE;
DROP TABLE IF EXISTS public.scholarships CASCADE;
DROP TABLE IF EXISTS public.chat_messages CASCADE;
DROP TABLE IF EXISTS public.notes CASCADE;
DROP TABLE IF EXISTS public.module_progress CASCADE;
DROP TABLE IF EXISTS public.applications CASCADE;
DROP TABLE IF EXISTS public.learning_paths CASCADE;
DROP TABLE IF EXISTS public.job_required_skills CASCADE;
DROP TABLE IF EXISTS public.jobs CASCADE;
DROP TABLE IF EXISTS public.resumes CASCADE;
DROP TABLE IF EXISTS public.student_skills CASCADE;
DROP TABLE IF EXISTS public.skills CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;

-- Drop existing types
DROP TYPE IF EXISTS public.user_role CASCADE;
DROP TYPE IF EXISTS public.application_status CASCADE;
DROP TYPE IF EXISTS public.opportunity_type CASCADE;
DROP TYPE IF EXISTS public.module_status CASCADE;

-- Drop existing extensions
DROP EXTENSION IF EXISTS "uuid-ossp" CASCADE;
DROP EXTENSION IF EXISTS pgcrypto CASCADE;

-- =====================================================================
-- 0. Extensions
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =====================================================================
-- 1. Enums
-- =====================================================================
CREATE TYPE user_role AS ENUM ('student', 'recruiter', 'academician', 'admin');
CREATE TYPE application_status AS ENUM ('applied', 'shortlisted', 'interview', 'offered', 'rejected', 'withdrawn');
CREATE TYPE opportunity_type AS ENUM ('internship', 'placement', 'live_project', 'fdp');
CREATE TYPE module_status AS ENUM ('locked', 'in_progress', 'completed');

-- =====================================================================
-- 2. Profiles Table
-- =====================================================================
CREATE TABLE public.profiles (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name text NOT NULL,
    role user_role NOT NULL DEFAULT 'student',
    institution text,
    company text,
    department text,
    avatar_url text,
    readiness_score numeric(5,2) DEFAULT 0,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

COMMENT ON TABLE public.profiles IS 'One row per authenticated user; role drives RBAC across the app.';

-- =====================================================================
-- 3. Skills Taxonomy
-- =====================================================================
CREATE TABLE public.skills (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text UNIQUE NOT NULL,
    category text NOT NULL,
    description text
);

-- =====================================================================
-- 4. Student Skills
-- =====================================================================
CREATE TABLE public.student_skills (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    skill_id uuid NOT NULL REFERENCES public.skills(id) ON DELETE CASCADE,
    proficiency int NOT NULL CHECK (proficiency BETWEEN 0 AND 100),
    source text DEFAULT 'self_assessed',
    updated_at timestamptz DEFAULT now(),
    UNIQUE(student_id, skill_id)
);

-- =====================================================================
-- 5. Resumes
-- =====================================================================
CREATE TABLE public.resumes (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    file_url text,
    raw_text text,
    parsed_at timestamptz DEFAULT now()
);

-- =====================================================================
-- 6. Jobs
-- =====================================================================
CREATE TABLE public.jobs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    posted_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    title text NOT NULL,
    company text NOT NULL,
    type opportunity_type NOT NULL DEFAULT 'internship',
    description text,
    location text,
    stipend_or_salary text,
    min_readiness_score numeric(5,2) DEFAULT 0,
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT now()
);

-- =====================================================================
-- 7. Job Required Skills
-- =====================================================================
CREATE TABLE public.job_required_skills (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_id uuid NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    skill_id uuid NOT NULL REFERENCES public.skills(id) ON DELETE CASCADE,
    min_proficiency int NOT NULL DEFAULT 50 CHECK (min_proficiency BETWEEN 0 AND 100),
    weight numeric(3,2) DEFAULT 1.0,
    UNIQUE(job_id, skill_id)
);

-- =====================================================================
-- 8. Learning Paths
-- =====================================================================
CREATE TABLE public.learning_paths (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    target_job_id uuid REFERENCES public.jobs(id) ON DELETE SET NULL,
    gap_summary text,
    modules jsonb NOT NULL DEFAULT '[]'::jsonb,
    generated_at timestamptz DEFAULT now()
);

-- =====================================================================
-- 9. Applications
-- =====================================================================
CREATE TABLE public.applications (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    job_id uuid NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    status application_status NOT NULL DEFAULT 'applied',
    match_score numeric(5,2),
    applied_at timestamptz DEFAULT now(),
    UNIQUE(student_id, job_id)
);

-- =====================================================================
-- 10. Module Progress
-- =====================================================================
CREATE TABLE public.module_progress (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    learning_path_id uuid NOT NULL REFERENCES public.learning_paths(id) ON DELETE CASCADE,
    module_key text NOT NULL,
    status module_status NOT NULL DEFAULT 'locked',
    completed_at timestamptz,
    UNIQUE(student_id, learning_path_id, module_key)
);

-- =====================================================================
-- 11. Notes
-- =====================================================================
CREATE TABLE public.notes (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    title text NOT NULL,
    raw_notes text NOT NULL,
    mermaid_syntax text,
    quiz jsonb,
    created_at timestamptz DEFAULT now()
);

-- =====================================================================
-- 12. Chat Messages
-- =====================================================================
CREATE TABLE public.chat_messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    role text NOT NULL CHECK (role IN ('user','assistant')),
    content text NOT NULL,
    created_at timestamptz DEFAULT now()
);

-- =====================================================================
-- 13. Scholarships
-- =====================================================================
CREATE TABLE public.scholarships (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    eligibility_criteria text,
    min_readiness_score numeric(5,2) DEFAULT 0,
    deadline date NOT NULL,
    link text
);

-- =====================================================================
-- 14. Notifications
-- =====================================================================
CREATE TABLE public.notifications (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    recipient_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    title text NOT NULL,
    body text,
    kind text DEFAULT 'general',
    is_read boolean DEFAULT false,
    created_at timestamptz DEFAULT now()
);

-- =====================================================================
-- 15. Row Level Security (Simple, no circular dependencies)
-- =====================================================================

-- Enable RLS on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.skills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_skills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.resumes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.learning_paths ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_required_skills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.module_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scholarships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Profiles: Users can read/update own profile
CREATE POLICY "profiles_read_own" ON public.profiles
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "profiles_insert_own" ON public.profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE USING (auth.uid() = id);

-- Skills: All authenticated users can read
CREATE POLICY "skills_read_all" ON public.skills
  FOR SELECT USING (auth.role() = 'authenticated');

-- Student Skills: Student can read/write own
CREATE POLICY "student_skills_own" ON public.student_skills
  FOR ALL USING (student_id = auth.uid());

-- Resumes: Student can read/write own
CREATE POLICY "resumes_own" ON public.resumes
  FOR ALL USING (student_id = auth.uid());

-- Learning Paths: Student can read/write own
CREATE POLICY "learning_paths_own" ON public.learning_paths
  FOR ALL USING (student_id = auth.uid());

-- Jobs: All authenticated users can read active jobs
CREATE POLICY "jobs_read_active" ON public.jobs
  FOR SELECT USING (is_active = true);

-- Jobs: Posters can read/write their own
CREATE POLICY "jobs_own" ON public.jobs
  FOR ALL USING (posted_by = auth.uid());

-- Job Required Skills: All authenticated can read
CREATE POLICY "job_required_skills_read" ON public.job_required_skills
  FOR SELECT USING (auth.role() = 'authenticated');

-- Applications: Students can manage own applications
CREATE POLICY "applications_own" ON public.applications
  FOR ALL USING (student_id = auth.uid());

-- Module Progress: Students can manage own
CREATE POLICY "module_progress_own" ON public.module_progress
  FOR ALL USING (student_id = auth.uid());

-- Notes: Students can manage own
CREATE POLICY "notes_own" ON public.notes
  FOR ALL USING (student_id = auth.uid());

-- Chat: Students can manage own
CREATE POLICY "chat_own" ON public.chat_messages
  FOR ALL USING (student_id = auth.uid());

-- Scholarships: All authenticated can read
CREATE POLICY "scholarships_read" ON public.scholarships
  FOR SELECT USING (auth.role() = 'authenticated');

-- Notifications: Recipients can read own
CREATE POLICY "notifications_own" ON public.notifications
  FOR ALL USING (recipient_id = auth.uid());

-- =====================================================================
-- 16. Auto-create Profile on User Signup
-- =====================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (
    new.id,
    COALESCE(new.raw_user_meta_data->>'full_name', 'New User'),
    CASE 
      WHEN new.raw_user_meta_data->>'role' = 'recruiter' THEN 'recruiter'::user_role
      WHEN new.raw_user_meta_data->>'role' = 'academician' THEN 'academician'::user_role
      WHEN new.raw_user_meta_data->>'role' = 'admin' THEN 'admin'::user_role
      ELSE 'student'::user_role
    END
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- =====================================================================
-- 17. SEED DATA - Demo Users and Content
-- =====================================================================

-- Insert demo auth users
INSERT INTO auth.users (
  id, instance_id, email, encrypted_password, email_confirmed_at, 
  raw_user_meta_data, aud, role
) VALUES
  ('11111111-1111-1111-1111-111111111001', '00000000-0000-0000-0000-000000000000', 
   'ansh@student.ayush.demo', crypt('Password123!', gen_salt('bf')), now(),
   '{"full_name":"Ansh Sharma","role":"student"}', 'authenticated', 'authenticated'),
  ('11111111-1111-1111-1111-111111111002', '00000000-0000-0000-0000-000000000000',
   'akshat@student.ayush.demo', crypt('Password123!', gen_salt('bf')), now(),
   '{"full_name":"Akshat Verma","role":"student"}', 'authenticated', 'authenticated'),
  ('11111111-1111-1111-1111-111111111003', '00000000-0000-0000-0000-000000000000',
   'tanmay@student.ayush.demo', crypt('Password123!', gen_salt('bf')), now(),
   '{"full_name":"Tanmay Gupta","role":"student"}', 'authenticated', 'authenticated'),
  ('11111111-1111-1111-1111-111111111004', '00000000-0000-0000-0000-000000000000',
   'sumit@student.ayush.demo', crypt('Password123!', gen_salt('bf')), now(),
   '{"full_name":"Sumit Yadav","role":"student"}', 'authenticated', 'authenticated'),
  ('11111111-1111-1111-1111-111111111005', '00000000-0000-0000-0000-000000000000',
   'bharat@student.ayush.demo', crypt('Password123!', gen_salt('bf')), now(),
   '{"full_name":"Bharat Singh","role":"student"}', 'authenticated', 'authenticated'),
  ('11111111-1111-1111-1111-111111111006', '00000000-0000-0000-0000-000000000000',
   'hardik@student.ayush.demo', crypt('Password123!', gen_salt('bf')), now(),
   '{"full_name":"Hardik Malhotra","role":"student"}', 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222001', '00000000-0000-0000-0000-000000000000',
   'recruiter@herbtech.demo', crypt('Password123!', gen_salt('bf')), now(),
   '{"full_name":"Priya Nair","role":"recruiter"}', 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222002', '00000000-0000-0000-0000-000000000000',
   'recruiter@ayurcorp.demo', crypt('Password123!', gen_salt('bf')), now(),
   '{"full_name":"Rohan Iyer","role":"recruiter"}', 'authenticated', 'authenticated'),
  ('33333333-3333-3333-3333-333333333001', '00000000-0000-0000-0000-000000000000',
   'prof.mehta@university.demo', crypt('Password123!', gen_salt('bf')), now(),
   '{"full_name":"Dr. Meera Mehta","role":"academician"}', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

-- Insert profiles (trigger should have created them, but ensure they exist)
INSERT INTO public.profiles (id, full_name, role, institution, company, department, readiness_score) VALUES
  ('11111111-1111-1111-1111-111111111001', 'Ansh Sharma', 'student', 'IIT Delhi - Dept. of Ayush Sciences', NULL, NULL, 72),
  ('11111111-1111-1111-1111-111111111002', 'Akshat Verma', 'student', 'BHU Institute of Medical Sciences', NULL, NULL, 58),
  ('11111111-1111-1111-1111-111111111003', 'Tanmay Gupta', 'student', 'AIIA New Delhi', NULL, NULL, 45),
  ('11111111-1111-1111-1111-111111111004', 'Sumit Yadav', 'student', 'NIA Jaipur', NULL, NULL, 81),
  ('11111111-1111-1111-1111-111111111005', 'Bharat Singh', 'student', 'IIT Delhi - Dept. of Ayush Sciences', NULL, NULL, 33),
  ('11111111-1111-1111-1111-111111111006', 'Hardik Malhotra', 'student', 'BHU Institute of Medical Sciences', NULL, NULL, 65),
  ('22222222-2222-2222-2222-222222222001', 'Priya Nair', 'recruiter', NULL, 'HerbTech Wellness Pvt Ltd', NULL, 0),
  ('22222222-2222-2222-2222-222222222002', 'Rohan Iyer', 'recruiter', NULL, 'AyurCorp Health Solutions', NULL, 0),
  ('33333333-3333-3333-3333-333333333001', 'Dr. Meera Mehta', 'academician', 'Central University', NULL, 'Ayush Curriculum & Research', 0)
ON CONFLICT (id) DO UPDATE SET
  full_name = EXCLUDED.full_name,
  role = EXCLUDED.role,
  institution = EXCLUDED.institution,
  company = EXCLUDED.company,
  department = EXCLUDED.department,
  readiness_score = EXCLUDED.readiness_score;

-- Insert skills
INSERT INTO public.skills (id, name, category, description) VALUES
  ('a1111111-0000-0000-0000-000000000001', 'Ayurvedic Pharmacology', 'Domain (Ayush)', 'Understanding of herbal drug action and formulation'),
  ('a1111111-0000-0000-0000-000000000002', 'Panchakarma Techniques', 'Domain (Ayush)', 'Practical detox/therapy procedures'),
  ('a1111111-0000-0000-0000-000000000003', 'Clinical Research Methodology', 'Domain (Ayush)', 'Designing and running clinical trials'),
  ('a1111111-0000-0000-0000-000000000004', 'Data Analysis (Python)', 'Technical', 'Pandas/NumPy based data analysis'),
  ('a1111111-0000-0000-0000-000000000005', 'Regulatory Affairs (AYUSH/FSSAI)', 'Domain (Ayush)', 'Compliance and licensing knowledge'),
  ('a1111111-0000-0000-0000-000000000006', 'Herbal Product Formulation', 'Domain (Ayush)', 'Nutraceutical/cosmeceutical formulation'),
  ('a1111111-0000-0000-0000-000000000007', 'Digital Health Records (EHR)', 'Technical', 'Working with EHR/EMR systems'),
  ('a1111111-0000-0000-0000-000000000008', 'Communication & Patient Counselling', 'Soft Skill', 'Patient-facing communication'),
  ('a1111111-0000-0000-0000-000000000009', 'Quality Control & GMP', 'Technical', 'Good Manufacturing Practice standards'),
  ('a1111111-0000-0000-0000-000000000010', 'Business Development', 'Soft Skill', 'Sales and partnership skills for Ayush startups')
ON CONFLICT (id) DO NOTHING;

-- Insert student skills
INSERT INTO public.student_skills (student_id, skill_id, proficiency, source) VALUES
  ('11111111-1111-1111-1111-111111111001', 'a1111111-0000-0000-0000-000000000001', 80, 'self_assessed'),
  ('11111111-1111-1111-1111-111111111001', 'a1111111-0000-0000-0000-000000000004', 70, 'resume_parsed'),
  ('11111111-1111-1111-1111-111111111001', 'a1111111-0000-0000-0000-000000000005', 40, 'self_assessed'),
  ('11111111-1111-1111-1111-111111111002', 'a1111111-0000-0000-0000-000000000002', 65, 'self_assessed'),
  ('11111111-1111-1111-1111-111111111002', 'a1111111-0000-0000-0000-000000000008', 55, 'self_assessed'),
  ('11111111-1111-1111-1111-111111111003', 'a1111111-0000-0000-0000-000000000003', 30, 'resume_parsed'),
  ('11111111-1111-1111-1111-111111111003', 'a1111111-0000-0000-0000-000000000004', 20, 'self_assessed'),
  ('11111111-1111-1111-1111-111111111004', 'a1111111-0000-0000-0000-000000000006', 85, 'resume_parsed'),
  ('11111111-1111-1111-1111-111111111004', 'a1111111-0000-0000-0000-000000000009', 75, 'self_assessed'),
  ('11111111-1111-1111-1111-111111111005', 'a1111111-0000-0000-0000-000000000010', 25, 'self_assessed'),
  ('11111111-1111-1111-1111-111111111006', 'a1111111-0000-0000-0000-000000000007', 60, 'resume_parsed'),
  ('11111111-1111-1111-1111-111111111006', 'a1111111-0000-0000-0000-000000000001', 50, 'self_assessed')
ON CONFLICT (student_id, skill_id) DO NOTHING;

-- Insert jobs
INSERT INTO public.jobs (id, posted_by, title, company, type, description, location, stipend_or_salary, min_readiness_score) VALUES
  ('b2222222-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222001', 'Ayurvedic Product Research Intern', 'HerbTech Wellness Pvt Ltd', 'internship', 'Assist in formulating and testing new herbal nutraceutical products.', 'Bengaluru', '₹15,000/month', 40),
  ('b2222222-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222001', 'Regulatory Affairs Associate', 'HerbTech Wellness Pvt Ltd', 'placement', 'Manage AYUSH/FSSAI licensing and compliance filings.', 'Bengaluru', '₹6.5 LPA', 60),
  ('b2222222-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222002', 'Clinical Research Associate', 'AyurCorp Health Solutions', 'placement', 'Coordinate clinical trials for Ayurvedic formulations.', 'Pune', '₹7.2 LPA', 70),
  ('b2222222-0000-0000-0000-000000000004', '22222222-2222-2222-2222-222222222002', 'Panchakarma Therapy Live Project', 'AyurCorp Health Solutions', 'live_project', 'Live project digitizing Panchakarma therapy protocols for a wellness chain.', 'Remote', 'Unpaid (credit-linked)', 30),
  ('b2222222-0000-0000-0000-000000000005', '33333333-3333-3333-3333-333333333001', 'Faculty Development Program: AI in Ayush Diagnostics', 'Central University', 'fdp', 'Workshop on applying AI/data-analysis tools to traditional diagnostics.', 'Delhi (Hybrid)', 'N/A', 0),
  ('b2222222-0000-0000-0000-000000000006', '22222222-2222-2222-2222-222222222001', 'Business Development Intern - Ayush Startups', 'HerbTech Wellness Pvt Ltd', 'internship', 'Support partnership outreach for herbal product distribution.', 'Mumbai', '₹12,000/month', 20)
ON CONFLICT (id) DO NOTHING;

-- Insert job required skills
INSERT INTO public.job_required_skills (job_id, skill_id, min_proficiency, weight) VALUES
  ('b2222222-0000-0000-0000-000000000001', 'a1111111-0000-0000-0000-000000000001', 50, 1.5),
  ('b2222222-0000-0000-0000-000000000001', 'a1111111-0000-0000-0000-000000000006', 40, 1.0),
  ('b2222222-0000-0000-0000-000000000002', 'a1111111-0000-0000-0000-000000000005', 60, 2.0),
  ('b2222222-0000-0000-0000-000000000002', 'a1111111-0000-0000-0000-000000000009', 40, 1.0),
  ('b2222222-0000-0000-0000-000000000003', 'a1111111-0000-0000-0000-000000000003', 65, 2.0),
  ('b2222222-0000-0000-0000-000000000003', 'a1111111-0000-0000-0000-000000000004', 40, 1.0),
  ('b2222222-0000-0000-0000-000000000004', 'a1111111-0000-0000-0000-000000000002', 50, 1.5),
  ('b2222222-0000-0000-0000-000000000004', 'a1111111-0000-0000-0000-000000000008', 40, 1.0),
  ('b2222222-0000-0000-0000-000000000005', 'a1111111-0000-0000-0000-000000000004', 30, 1.0),
  ('b2222222-0000-0000-0000-000000000006', 'a1111111-0000-0000-0000-000000000010', 30, 1.5)
ON CONFLICT (job_id, skill_id) DO NOTHING;

-- Insert applications
INSERT INTO public.applications (student_id, job_id, status, match_score) VALUES
  ('11111111-1111-1111-1111-111111111001', 'b2222222-0000-0000-0000-000000000001', 'shortlisted', 78.5),
  ('11111111-1111-1111-1111-111111111004', 'b2222222-0000-0000-0000-000000000004', 'applied', 88.0),
  ('11111111-1111-1111-1111-111111111006', 'b2222222-0000-0000-0000-000000000005', 'offered', 90.0)
ON CONFLICT (student_id, job_id) DO NOTHING;

-- Insert scholarships
INSERT INTO public.scholarships (name, eligibility_criteria, min_readiness_score, deadline, link) VALUES
  ('National Ayush Merit Scholarship 2026', 'Students with readiness score above 50 in accredited Ayush institutions', 50, '2026-10-15', 'https://ayush.gov.in/scholarships/merit-2026'),
  ('Central Sector Scheme for Ayush PG Scholars', 'Postgraduate Ayush students; no minimum readiness score', 0, '2026-09-30', 'https://ayush.gov.in/scholarships/pg-2026')
ON CONFLICT DO NOTHING;

-- Insert notifications
INSERT INTO public.notifications (recipient_id, title, body, kind) VALUES
  ('11111111-1111-1111-1111-111111111003', 'Scholarship Deadline Approaching', 'Central Sector Scheme for Ayush PG Scholars closes on 2026-09-30.', 'scholarship'),
  ('11111111-1111-1111-1111-111111111005', 'New Opportunity Unlocked', 'You have unlocked "Business Development Intern - Ayush Startups" after improving your readiness score.', 'opportunity');

-- =====================================================================
-- End of Clean Schema
-- =====================================================================
