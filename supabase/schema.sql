-- =====================================================================
-- Ministry of Ayush — Academia-Industry Collaboration Portal
-- Supabase (PostgreSQL) schema, RLS policies, and seed/dummy data
-- =====================================================================
-- Run this in the Supabase SQL editor (or via `supabase db push`).
-- Assumes Supabase Auth is used for login; auth.users is the source
-- of truth for identity, and `profiles` extends it with app data.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Extensions
-- ---------------------------------------------------------------------
create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. Enums
-- ---------------------------------------------------------------------
create type user_role as enum ('student', 'recruiter', 'academician', 'admin');
create type application_status as enum ('applied', 'shortlisted', 'interview', 'offered', 'rejected', 'withdrawn');
create type opportunity_type as enum ('internship', 'placement', 'live_project', 'fdp');
create type module_status as enum ('locked', 'in_progress', 'completed');

-- ---------------------------------------------------------------------
-- 2. Profiles (extends auth.users) — role-based access control anchor
-- ---------------------------------------------------------------------
create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    full_name text not null,
    role user_role not null default 'student',
    institution text,
    company text,               -- for recruiters
    department text,            -- for academicians
    avatar_url text,
    readiness_score numeric(5,2) default 0,   -- 0-100, computed placement-readiness
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

comment on table public.profiles is 'One row per authenticated user; role drives RBAC across the app.';

-- Helper function used inside RLS policies to read the caller's role
-- without recursive RLS evaluation issues.
create or replace function public.current_role()
returns user_role
language sql
security definer
stable
as $$
  select role from public.profiles where id = auth.uid();
$$;

-- ---------------------------------------------------------------------
-- 3. Skills taxonomy
-- ---------------------------------------------------------------------
create table public.skills (
    id uuid primary key default uuid_generate_v4(),
    name text unique not null,
    category text not null,          -- e.g. 'Technical', 'Domain (Ayurveda/Ayush)', 'Soft Skill'
    description text
);

-- Student <-> Skill (self-declared / assessed proficiency)
create table public.student_skills (
    id uuid primary key default uuid_generate_v4(),
    student_id uuid not null references public.profiles(id) on delete cascade,
    skill_id uuid not null references public.skills(id) on delete cascade,
    proficiency int not null check (proficiency between 0 and 100),
    source text default 'self_assessed',   -- self_assessed | resume_parsed | gemini_inferred
    updated_at timestamptz default now(),
    unique (student_id, skill_id)
);

-- ---------------------------------------------------------------------
-- 4. Resumes & AI-generated Learning Paths (Gemini gap analysis output)
-- ---------------------------------------------------------------------
create table public.resumes (
    id uuid primary key default uuid_generate_v4(),
    student_id uuid not null references public.profiles(id) on delete cascade,
    file_url text,             -- Supabase Storage path
    raw_text text,             -- extracted text sent to Gemini
    parsed_at timestamptz default now()
);

-- ---------------------------------------------------------------------
-- 5. Jobs / Internships / FDPs / Live Projects (posted by recruiters/academicians)
-- ---------------------------------------------------------------------
create table public.jobs (
    id uuid primary key default uuid_generate_v4(),
    posted_by uuid not null references public.profiles(id) on delete cascade,
    title text not null,
    company text not null,
    type opportunity_type not null default 'internship',
    description text,
    location text,
    stipend_or_salary text,
    min_readiness_score numeric(5,2) default 0,  -- unlock threshold
    is_active boolean default true,
    created_at timestamptz default now()
);

create table public.job_required_skills (
    id uuid primary key default uuid_generate_v4(),
    job_id uuid not null references public.jobs(id) on delete cascade,
    skill_id uuid not null references public.skills(id) on delete cascade,
    min_proficiency int not null default 50 check (min_proficiency between 0 and 100),
    weight numeric(3,2) default 1.0,   -- relative importance for matching
    unique (job_id, skill_id)
);

-- learning_paths references jobs, so it is defined after the jobs table above
create table public.learning_paths (
    id uuid primary key default uuid_generate_v4(),
    student_id uuid not null references public.profiles(id) on delete cascade,
    target_job_id uuid references public.jobs(id) on delete set null,
    gap_summary text,
    modules jsonb not null default '[]'::jsonb,   -- structured JSON from Gemini
    generated_at timestamptz default now()
);

-- ---------------------------------------------------------------------
-- 6. Applications & Opportunity Unlocking
-- ---------------------------------------------------------------------
create table public.applications (
    id uuid primary key default uuid_generate_v4(),
    student_id uuid not null references public.profiles(id) on delete cascade,
    job_id uuid not null references public.jobs(id) on delete cascade,
    status application_status not null default 'applied',
    match_score numeric(5,2),           -- computed at apply-time
    applied_at timestamptz default now(),
    unique (student_id, job_id)
);

create table public.module_progress (
    id uuid primary key default uuid_generate_v4(),
    student_id uuid not null references public.profiles(id) on delete cascade,
    learning_path_id uuid not null references public.learning_paths(id) on delete cascade,
    module_key text not null,       -- key inside the learning_paths.modules JSON
    status module_status not null default 'locked',
    completed_at timestamptz,
    unique (student_id, learning_path_id, module_key)
);

-- ---------------------------------------------------------------------
-- 7. AI Study Companion: Notes, Flowcharts, Quizzes
-- ---------------------------------------------------------------------
create table public.notes (
    id uuid primary key default uuid_generate_v4(),
    student_id uuid not null references public.profiles(id) on delete cascade,
    title text not null,
    raw_notes text not null,
    mermaid_syntax text,          -- Gemini-generated Mermaid.js flowchart
    quiz jsonb,                   -- Gemini-generated quiz JSON
    created_at timestamptz default now()
);

create table public.chat_messages (
    id uuid primary key default uuid_generate_v4(),
    student_id uuid not null references public.profiles(id) on delete cascade,
    role text not null check (role in ('user','assistant')),
    content text not null,
    created_at timestamptz default now()
);

-- ---------------------------------------------------------------------
-- 8. Scholarships & Notifications (event/cron driven alerts)
-- ---------------------------------------------------------------------
create table public.scholarships (
    id uuid primary key default uuid_generate_v4(),
    name text not null,
    eligibility_criteria text,
    min_readiness_score numeric(5,2) default 0,
    deadline date not null,
    link text
);

create table public.notifications (
    id uuid primary key default uuid_generate_v4(),
    recipient_id uuid not null references public.profiles(id) on delete cascade,
    title text not null,
    body text,
    kind text default 'general',   -- general | scholarship | deadline | opportunity
    is_read boolean default false,
    created_at timestamptz default now()
);

-- ---------------------------------------------------------------------
-- 9. Row Level Security
-- ---------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.skills enable row level security;
alter table public.student_skills enable row level security;
alter table public.resumes enable row level security;
alter table public.learning_paths enable row level security;
alter table public.jobs enable row level security;
alter table public.job_required_skills enable row level security;
alter table public.applications enable row level security;
alter table public.module_progress enable row level security;
alter table public.notes enable row level security;
alter table public.chat_messages enable row level security;
alter table public.scholarships enable row level security;
alter table public.notifications enable row level security;

-- profiles: users read/update themselves; recruiters/academicians/admin can view students
create policy "profiles_select_self_or_staff" on public.profiles
  for select using (
    id = auth.uid()
    or public.current_role() in ('recruiter','academician','admin')
  );

create policy "profiles_update_self" on public.profiles
  for update using (id = auth.uid());

create policy "profiles_insert_self" on public.profiles
  for insert with check (id = auth.uid());

-- skills: readable by everyone authenticated; writable by academician/admin
create policy "skills_select_all" on public.skills for select using (auth.role() = 'authenticated');
create policy "skills_write_academic" on public.skills for all using (public.current_role() in ('academician','admin'));

-- student_skills: student owns their rows; staff can read for analytics
create policy "student_skills_owner" on public.student_skills
  for all using (student_id = auth.uid())
  with check (student_id = auth.uid());

create policy "student_skills_staff_read" on public.student_skills
  for select using (public.current_role() in ('recruiter','academician','admin'));

-- resumes: student-owned only
create policy "resumes_owner" on public.resumes
  for all using (student_id = auth.uid()) with check (student_id = auth.uid());

-- learning_paths: student reads own; academicians can read for mentoring
create policy "learning_paths_owner" on public.learning_paths
  for all using (student_id = auth.uid()) with check (student_id = auth.uid());

create policy "learning_paths_staff_read" on public.learning_paths
  for select using (public.current_role() in ('academician','admin'));

-- jobs: everyone authenticated can read active jobs; poster (recruiter/academician) manages own
create policy "jobs_select_active" on public.jobs
  for select using (is_active = true or posted_by = auth.uid() or public.current_role() = 'admin');

create policy "jobs_insert_staff" on public.jobs
  for insert with check (public.current_role() in ('recruiter','academician','admin'));

create policy "jobs_modify_owner" on public.jobs
  for update using (posted_by = auth.uid() or public.current_role() = 'admin');

create policy "jobs_delete_owner" on public.jobs
  for delete using (posted_by = auth.uid() or public.current_role() = 'admin');

-- job_required_skills: readable by all authenticated, writable by job owner
create policy "jrs_select_all" on public.job_required_skills for select using (auth.role() = 'authenticated');
create policy "jrs_write_owner" on public.job_required_skills
  for all using (
    exists (select 1 from public.jobs j where j.id = job_id and (j.posted_by = auth.uid() or public.current_role() = 'admin'))
  );

-- applications: student manages own; recruiter sees applications to their jobs
create policy "applications_student_owner" on public.applications
  for all using (student_id = auth.uid()) with check (student_id = auth.uid());

create policy "applications_recruiter_read" on public.applications
  for select using (
    exists (select 1 from public.jobs j where j.id = job_id and j.posted_by = auth.uid())
    or public.current_role() = 'admin'
  );

create policy "applications_recruiter_update_status" on public.applications
  for update using (
    exists (select 1 from public.jobs j where j.id = job_id and j.posted_by = auth.uid())
  );

-- module_progress: student-owned
create policy "module_progress_owner" on public.module_progress
  for all using (student_id = auth.uid()) with check (student_id = auth.uid());

-- notes & chat_messages: private to the student
create policy "notes_owner" on public.notes
  for all using (student_id = auth.uid()) with check (student_id = auth.uid());

create policy "chat_owner" on public.chat_messages
  for all using (student_id = auth.uid()) with check (student_id = auth.uid());

-- scholarships: readable by all authenticated; writable by admin/academician
create policy "scholarships_select_all" on public.scholarships for select using (auth.role() = 'authenticated');
create policy "scholarships_write_staff" on public.scholarships for all using (public.current_role() in ('academician','admin'));

-- notifications: recipient-owned
create policy "notifications_owner" on public.notifications
  for all using (recipient_id = auth.uid()) with check (recipient_id = auth.uid());

-- ---------------------------------------------------------------------
-- 10. Auto-create a profile row when a new auth user signs up
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', 'New User'),
    coalesce((new.raw_user_meta_data->>'role')::user_role, 'student')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- =====================================================================
-- 11. SEED / DUMMY DATA
-- =====================================================================
-- NOTE: In production, auth.users rows are created via Supabase Auth
-- (sign-up flow), which triggers handle_new_user() above. For this
-- hackathon prototype we insert directly into auth.users + profiles
-- with fixed UUIDs so the FastAPI/React demo has deterministic IDs
-- to reference. Passwords below are for local/demo use only.
-- =====================================================================

-- 11.1 Demo auth users (students, recruiters, academician)
insert into auth.users (id, instance_id, email, encrypted_password, email_confirmed_at, raw_user_meta_data, aud, role)
values
  ('11111111-1111-1111-1111-111111111001', '00000000-0000-0000-0000-000000000000', 'ansh@student.ayush.demo',   crypt('Password123!', gen_salt('bf')), now(), '{"full_name":"Ansh Sharma","role":"student"}', 'authenticated','authenticated'),
  ('11111111-1111-1111-1111-111111111002', '00000000-0000-0000-0000-000000000000', 'akshat@student.ayush.demo', crypt('Password123!', gen_salt('bf')), now(), '{"full_name":"Akshat Verma","role":"student"}', 'authenticated','authenticated'),
  ('11111111-1111-1111-1111-111111111003', '00000000-0000-0000-0000-000000000000', 'tanmay@student.ayush.demo', crypt('Password123!', gen_salt('bf')), now(), '{"full_name":"Tanmay Gupta","role":"student"}', 'authenticated','authenticated'),
  ('11111111-1111-1111-1111-111111111004', '00000000-0000-0000-0000-000000000000', 'sumit@student.ayush.demo',  crypt('Password123!', gen_salt('bf')), now(), '{"full_name":"Sumit Yadav","role":"student"}', 'authenticated','authenticated'),
  ('11111111-1111-1111-1111-111111111005', '00000000-0000-0000-0000-000000000000', 'bharat@student.ayush.demo', crypt('Password123!', gen_salt('bf')), now(), '{"full_name":"Bharat Singh","role":"student"}', 'authenticated','authenticated'),
  ('11111111-1111-1111-1111-111111111006', '00000000-0000-0000-0000-000000000000', 'hardik@student.ayush.demo', crypt('Password123!', gen_salt('bf')), now(), '{"full_name":"Hardik Malhotra","role":"student"}', 'authenticated','authenticated'),
  ('22222222-2222-2222-2222-222222222001', '00000000-0000-0000-0000-000000000000', 'recruiter@herbtech.demo',   crypt('Password123!', gen_salt('bf')), now(), '{"full_name":"Priya Nair","role":"recruiter"}', 'authenticated','authenticated'),
  ('22222222-2222-2222-2222-222222222002', '00000000-0000-0000-0000-000000000000', 'recruiter@ayurcorp.demo',   crypt('Password123!', gen_salt('bf')), now(), '{"full_name":"Rohan Iyer","role":"recruiter"}', 'authenticated','authenticated'),
  ('33333333-3333-3333-3333-333333333001', '00000000-0000-0000-0000-000000000000', 'prof.mehta@university.demo', crypt('Password123!', gen_salt('bf')), now(), '{"full_name":"Dr. Meera Mehta","role":"academician"}', 'authenticated','authenticated')
on conflict (id) do nothing;

-- 11.2 Profiles (in case trigger didn't fire due to direct insert order; upsert to be safe)
insert into public.profiles (id, full_name, role, institution, company, department, readiness_score)
values
  ('11111111-1111-1111-1111-111111111001', 'Ansh Sharma',      'student', 'IIT Delhi - Dept. of Ayush Sciences', null, null, 72),
  ('11111111-1111-1111-1111-111111111002', 'Akshat Verma',     'student', 'BHU Institute of Medical Sciences',    null, null, 58),
  ('11111111-1111-1111-1111-111111111003', 'Tanmay Gupta',     'student', 'AIIA New Delhi',                       null, null, 45),
  ('11111111-1111-1111-1111-111111111004', 'Sumit Yadav',      'student', 'NIA Jaipur',                           null, null, 81),
  ('11111111-1111-1111-1111-111111111005', 'Bharat Singh',     'student', 'IIT Delhi - Dept. of Ayush Sciences',  null, null, 33),
  ('11111111-1111-1111-1111-111111111006', 'Hardik Malhotra',  'student', 'BHU Institute of Medical Sciences',    null, null, 65),
  ('22222222-2222-2222-2222-222222222001', 'Priya Nair',   'recruiter', null, 'HerbTech Wellness Pvt Ltd', null, 0),
  ('22222222-2222-2222-2222-222222222002', 'Rohan Iyer',   'recruiter', null, 'AyurCorp Health Solutions', null, 0),
  ('33333333-3333-3333-3333-333333333001', 'Dr. Meera Mehta', 'academician', 'Central University', null, 'Ayush Curriculum & Research', 0)
on conflict (id) do update set
  full_name = excluded.full_name,
  role = excluded.role,
  institution = excluded.institution,
  company = excluded.company,
  department = excluded.department,
  readiness_score = excluded.readiness_score;

-- 11.3 Skills taxonomy
insert into public.skills (id, name, category, description) values
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
on conflict (id) do nothing;

-- 11.4 Student skill proficiencies (mix of strong/weak to drive gap analysis demo)
insert into public.student_skills (student_id, skill_id, proficiency, source) values
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
on conflict (student_id, skill_id) do nothing;

-- 11.5 Dummy jobs / internships / FDPs / live projects
insert into public.jobs (id, posted_by, title, company, type, description, location, stipend_or_salary, min_readiness_score) values
  ('b2222222-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222001', 'Ayurvedic Product Research Intern', 'HerbTech Wellness Pvt Ltd', 'internship', 'Assist in formulating and testing new herbal nutraceutical products.', 'Bengaluru', '₹15,000/month', 40),
  ('b2222222-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222001', 'Regulatory Affairs Associate', 'HerbTech Wellness Pvt Ltd', 'placement', 'Manage AYUSH/FSSAI licensing and compliance filings.', 'Bengaluru', '₹6.5 LPA', 60),
  ('b2222222-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222002', 'Clinical Research Associate', 'AyurCorp Health Solutions', 'placement', 'Coordinate clinical trials for Ayurvedic formulations.', 'Pune', '₹7.2 LPA', 70),
  ('b2222222-0000-0000-0000-000000000004', '22222222-2222-2222-2222-222222222002', 'Panchakarma Therapy Live Project', 'AyurCorp Health Solutions', 'live_project', 'Live project digitizing Panchakarma therapy protocols for a wellness chain.', 'Remote', 'Unpaid (credit-linked)', 30),
  ('b2222222-0000-0000-0000-000000000005', '33333333-3333-3333-3333-333333333001', 'Faculty Development Program: AI in Ayush Diagnostics', 'Central University', 'fdp', 'Workshop on applying AI/data-analysis tools to traditional diagnostics.', 'Delhi (Hybrid)', 'N/A', 0),
  ('b2222222-0000-0000-0000-000000000006', '22222222-2222-2222-2222-222222222001', 'Business Development Intern - Ayush Startups', 'HerbTech Wellness Pvt Ltd', 'internship', 'Support partnership outreach for herbal product distribution.', 'Mumbai', '₹12,000/month', 20)
on conflict (id) do nothing;

-- 11.6 Required skills per job (drives the matching algorithm)
insert into public.job_required_skills (job_id, skill_id, min_proficiency, weight) values
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
on conflict (job_id, skill_id) do nothing;

-- 11.7 Sample applications
insert into public.applications (student_id, job_id, status, match_score) values
  ('11111111-1111-1111-1111-111111111001', 'b2222222-0000-0000-0000-000000000001', 'shortlisted', 78.5),
  ('11111111-1111-1111-1111-111111111004', 'b2222222-0000-0000-0000-000000000004', 'applied', 88.0),
  ('11111111-1111-1111-1111-111111111006', 'b2222222-0000-0000-0000-000000000005', 'offered', 90.0)
on conflict (student_id, job_id) do nothing;

-- 11.8 Sample scholarships (for notification/cron demo)
insert into public.scholarships (name, eligibility_criteria, min_readiness_score, deadline, link) values
  ('National Ayush Merit Scholarship 2026', 'Students with readiness score above 50 in accredited Ayush institutions', 50, '2026-10-15', 'https://ayush.gov.in/scholarships/merit-2026'),
  ('Central Sector Scheme for Ayush PG Scholars', 'Postgraduate Ayush students; no minimum readiness score', 0, '2026-09-30', 'https://ayush.gov.in/scholarships/pg-2026')
on conflict do nothing;

-- 11.9 Sample notifications
insert into public.notifications (recipient_id, title, body, kind) values
  ('11111111-1111-1111-1111-111111111003', 'Scholarship Deadline Approaching', 'Central Sector Scheme for Ayush PG Scholars closes on 2026-09-30.', 'scholarship'),
  ('11111111-1111-1111-1111-111111111005', 'New Opportunity Unlocked', 'You have unlocked "Business Development Intern - Ayush Startups" after improving your readiness score.', 'opportunity');

-- =====================================================================
-- End of schema + seed data
-- =====================================================================
