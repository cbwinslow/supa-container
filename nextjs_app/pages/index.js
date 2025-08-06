import { useSession, useSupabaseClient } from '@supabase/auth-helpers-react';
import { Auth } from '@supabase/auth-ui-react';
import { ThemeSupa } from '@supabase/auth-ui-shared';
import Dashboard from './dashboard';

export default function Home() {
  const session = useSession();
  const supabase = useSupabaseClient();

  return (
    <div className="min-h-screen bg-gray-900">
      {!session ? (
        <div className="flex items-center justify-center h-screen">
          <div className="w-full max-w-md p-8 space-y-8 bg-gray-800 rounded-lg shadow-lg">
            <h1 className="text-3xl font-bold text-center text-white">Welcome to the RAG Platform</h1>
            <Auth
              supabaseClient={supabase}
              appearance={{ theme: ThemeSupa }}
              theme="dark"
              providers={['github', 'gitlab']}
            />
          </div>
        </div>
      ) : (
        <Dashboard />
      )}
    </div>
  );
}
