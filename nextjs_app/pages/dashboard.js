import { useState, useEffect, useRef } from 'react';
import { useSupabaseClient, useUser } from '@supabase/auth-helpers-react';
import Sidebar from '../components/Sidebar';
import Message from '../components/Message';

export default function Dashboard() {
    const supabase = useSupabaseClient();
    const user = useUser();
    const [conversations, setConversations] = useState([]);
    const [activeConversation, setActiveConversation] = useState(null);
    const [messages, setMessages] = useState([]);
    const [query, setQuery] = useState('');
    const [models, setModels] = useState([]);
    const [selectedModel, setSelectedModel] = useState('');
    const [systemPrompt, setSystemPrompt] = useState('');
    const [isLoading, setIsLoading] = useState(false);
    const messagesEndRef = useRef(null);

    useEffect(() => {
        const fetchModels = async () => {
            try {
                const res = await fetch('/api/models');
                const data = await res.json();
                setModels(data.data || []);
                if (data.data?.length > 0) {
                    setSelectedModel(data.data[0].id);
                }
            } catch (error) {
                console.error("Failed to fetch models:", error);
            }
        };
        fetchModels();
    }, []);

    useEffect(() => {
        const fetchMessages = async () => {
            if (activeConversation) {
                const { data, error } = await supabase
                    .from('messages')
                    .select('role, content')
                    .eq('session_id', activeConversation.id)
                    .order('created_at');
                if (error) console.error("Error fetching messages:", error);
                else setMessages(data);
            } else {
                setMessages([]);
            }
        };
        fetchMessages();
    }, [activeConversation, supabase]);

    useEffect(() => {
        messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
    }, [messages]);

    const handleQuery = async () => {
        if (!query || !activeConversation) return;
        setIsLoading(true);
        const userMessage = { role: 'user', content: query };
        setMessages(prev => [...prev, userMessage]);
        setQuery('');

        const { data: { session } } = await supabase.auth.getSession();
        const response = await fetch('/api/chat/stream', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${session.access_token}`
            },
            body: JSON.stringify({
                message: query,
                session_id: activeConversation.id,
                metadata: { model: selectedModel, system_prompt: systemPrompt }
            })
        });

        if (!response.body) {
            setIsLoading(false);
            return;
        }

        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let assistantResponse = { role: 'assistant', content: '' };
        setMessages(prev => [...prev, assistantResponse]);

        while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            const chunk = decoder.decode(value);
            const lines = chunk.split('\n');
            for (const line of lines) {
                if (line.startsWith('data: ')) {
                    const jsonStr = line.substring(6);
                    if (jsonStr.trim()) {
                        const data = JSON.parse(jsonStr);
                        if (data.type === 'text') {
                            assistantResponse.content += data.content;
                            setMessages(prev => [...prev.slice(0, -1), { ...assistantResponse }]);
                        }
                    }
                }
            }
        }
        setIsLoading(false);
    };

    return (
        <div className="flex h-screen bg-gray-900 text-white">
            <Sidebar
                conversations={conversations}
                setConversations={setConversations}
                activeConversation={activeConversation}
                setActiveConversation={setActiveConversation}
            />
            <div className="flex-1 flex flex-col">
                <div className="flex-1 overflow-y-auto">
                    {messages.map((msg, index) => <Message key={index} message={msg} />)}
                    <div ref={messagesEndRef} />
                </div>
                <div className="p-4 bg-gray-800 border-t border-gray-700">
                    <div className="max-w-4xl mx-auto">
                        <div className="flex items-center space-x-4">
                            <textarea
                                value={query}
                                onChange={(e) => setQuery(e.target.value)}
                                onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleQuery(); } }}
                                placeholder="Ask the agent anything..."
                                className="w-full p-2 rounded bg-gray-700 text-white resize-none"
                                rows={1}
                            />
                            <button onClick={handleQuery} disabled={isLoading || !query} className="bg-blue-500 hover:bg-blue-600 text-white font-bold py-2 px-4 rounded disabled:opacity-50">
                                Send
                            </button>
                        </div>
                        <div className="flex items-center space-x-4 mt-2">
                            <select value={selectedModel} onChange={(e) => setSelectedModel(e.target.value)} className="bg-gray-700 text-white p-2 rounded">
                                {models.map(model => <option key={model.id} value={model.id}>{model.id}</option>)}
                            </select>
                            <input
                                type="text"
                                value={systemPrompt}
                                onChange={(e) => setSystemPrompt(e.target.value)}
                                placeholder="Custom system prompt..."
                                className="w-full p-2 rounded bg-gray-700 text-white"
                            />
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
}