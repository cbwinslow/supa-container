import { useEffect, useState } from "react";
import { supabase } from "../lib/supabaseClient";

export default function Home() {
  const [session, setSession] = useState(null);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
    });
  }, []);

  if (!session) {
    return (
      <button onClick={() => supabase.auth.signInWithOAuth({ provider: 'github' })}>
        Login with GitHub
      </button>
    );
  }
  return <div>Signed in as {session.user.email}</div>;
}
