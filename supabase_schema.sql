-- ATS Resume Agent — Supabase Schema
-- Run this in your Supabase SQL Editor before activating the workflow

-- Jobs table: tracks every processed job to avoid duplicate resumes
create table if not exists jobs (
  id           bigserial primary key,
  job_url      text unique not null,
  job_title    text,
  company      text,
  processed_at timestamptz default now()
);

-- Index for fast duplicate lookups (the workflow queries by job_url frequently)
create index if not exists idx_jobs_job_url on jobs(job_url);

-- Optional: view to see today's processed jobs
create or replace view todays_jobs as
  select job_title, company, job_url, processed_at
  from jobs
  where processed_at::date = current_date
  order by processed_at desc;
