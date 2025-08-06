import { useState } from 'react';
import { useSupabaseClient, useUser } from '@supabase/auth-helpers-react';

export default function Dashboard() {
    const supabase = useSupabaseClient();
    const user = useUser();
    const [file, setFile] = useState(null);
    const [query, setQuery] = useState('');
    const [answer, setAnswer] = useState('');
    const [isLoading, setIsLoading] = useState(false);
    const [message, setMessage] = useState('');

    const handleFileChange = (e) => {
        setFile(e.target.files[0]);
    };

    const handleIngest = async () => {
        if (!file) {
            setMessage('Please select a file to ingest.');
            return;
        }
        setIsLoading(true);
        setMessage(`Ingesting ${file.name}...`);
        const { data: { session } } = await supabase.auth.getSession();
        const formData = new FormData();
        formData.append('file', file);

        try {
            const response = await fetch('/api/ingest', {
                method: 'POST',
                headers: { 'Authorization': `Bearer ${session.access_token}` },
                body: formData,
            });
            const result = await response.json();
            if (!response.ok) throw new Error(result.detail);
            setMessage(result.message);
        } catch (error) {
            setMessage(`Ingestion failed: ${error.message}`);
        } finally {
            setIsLoading(false);
        }
    };

    const handleQuery = async () => {
        if (!query) {
            setMessage('Please enter a query.');
            return;
        }
        setIsLoading(true);
        setAnswer('');
        setMessage(`Querying with: "${query}"`);
        const { data: { session } } = await supabase.auth.getSession();

        try {
            const response = await fetch(`/api/query?q=${encodeURIComponent(query)}`, {
                method: 'POST',
                headers: { 'Authorization': `Bearer ${session.access_token}` },
            });
            const result = await response.json();
            if (!response.ok) throw new Error(result.detail);
            setAnswer(result.answer);
            setMessage('Query successful.');
        } catch (error) {
            setMessage(`Query failed: ${error.message}`);
        } finally {
            setIsLoading(false);
        }
    };

    return (
        <div className="min-h-screen bg-gray-900 text-white flex flex-col items-center p-4">
            <div className="w-full max-w-4xl">
                <div className="flex justify-between items-center mb-8">
                    <h1 className="text-3xl">RAG Application Dashboard</h1>
                    <button
                        onClick={() => supabase.auth.signOut()}
                        className="bg-red-500 hover:bg-red-600 text-white font-bold py-2 px-4 rounded"
                    >
                        Sign Out
                    </button>
                </div>

                <div className="bg-gray-800 p-6 rounded-lg mb-8">
                    <h2 className="text-2xl mb-4">Ingest Documents</h2>
                    <div className="flex items-center space-x-4">
                        <input type="file" onChange={handleFileChange} className="file:mr-4 file:py-2 file:px-4 file:rounded-full file:border-0 file:text-sm file:font-semibold file:bg-violet-50 file:text-violet-700 hover:file:bg-violet-100"/>
                        <button onClick={handleIngest} disabled={isLoading || !file} className="bg-blue-500 hover:bg-blue-600 text-white font-bold py-2 px-4 rounded disabled:opacity-50">
                            {isLoading ? 'Ingesting...' : 'Ingest'}
                        </button>
                    </div>
                </div>

                <div className="bg-gray-800 p-6 rounded-lg">
                    <h2 className="text-2xl mb-4">Query Your Documents</h2>
                    <div className="flex items-center space-x-4 mb-4">
                        <input
                            type="text"
                            value={query}
                            onChange={(e) => setQuery(e.target.value)}
                            placeholder="Ask a question about your documents"
                            className="w-full p-2 rounded bg-gray-700 text-white"
                        />
                        <button onClick={handleQuery} disabled={isLoading || !query} className="bg-green-500 hover:bg-green-600 text-white font-bold py-2 px-4 rounded disabled:opacity-50">
                            {isLoading ? 'Querying...' : 'Query'}
                        </button>
                    </div>
                    {message && <p className="text-sm text-gray-400 my-4">{message}</p>}
                    {answer && (
                        <div className="bg-gray-700 p-4 rounded">
                            <h3 className="text-xl mb-2">Answer:</h3>
                            <p>{answer}</p>
                        </div>
                    )}
                </div>
            </div>
        </div>
    );
}
