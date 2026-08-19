import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

// Check if credentials are placeholders or empty
export const isSupabaseConfigured = 
  supabaseUrl && 
  supabaseAnonKey && 
  supabaseUrl !== 'https://pnkfjbtvevydicosotgj.supabase.co' && // Avoid placeholder URL if it's inactive
  supabaseAnonKey !== 'YOUR_SUPABASE_ANON_KEY_HERE' &&
  !supabaseAnonKey.startsWith('YOUR_');

let supabaseInstance = null;

if (isSupabaseConfigured) {
  try {
    supabaseInstance = createClient(supabaseUrl, supabaseAnonKey);
  } catch (error) {
    console.error('Failed to initialize Supabase client:', error);
  }
} else {
  console.warn(
    'Supabase is not configured or is using placeholder credentials. Falling back to Local Storage database mode.'
  );
}

export const supabase = supabaseInstance;
