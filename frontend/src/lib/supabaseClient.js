import { createClient } from '@supabase/supabase-js';

// Frontend uses the ANON key only — RLS policies in schema.sql
// enforce per-row access. Never expose the service-role key here.
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

export const supabase = createClient(supabaseUrl, supabaseAnonKey);

// Helper to get the current access token for calling the FastAPI backend
export async function getAccessToken() {
  const { data } = await supabase.auth.getSession();
  return data?.session?.access_token ?? null;
}

export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL; // e.g. https://ayush-portal-api.onrender.com
