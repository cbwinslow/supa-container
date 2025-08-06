import { useState, useEffect } from 'react';
import { useSupabaseClient, useUser } from '@supabase/auth-helpers-react';

const Sidebar = ({ activeConversation, setActiveConversation, conversations, setConversations }) => {
    const supabase = useSupabaseClient();
    const user = useUser();

    useEffect(() => {
        const fetchConversations = async () => {
            if (user) {
                const { data, error } = await supabase
                    .from('sessions')
                    .select('id, metadata, created_at')
                    .eq('user_id', user.id)
                    .order('created_at', { ascending: false });

                if (error) {
                    console.error('Error fetching conversations:', error);
                } else {
                    setConversations(data.map(c => ({ id: c.id, name: c.metadata?.name || `Chat from ${new Date(c.created_at).toLocaleDateString()}` })));
                }
            }
        };
        fetchConversations();
    }, [user, supabase, setConversations]);

    const createNewChat = async () => {
        const { data, error } = await supabase
            .from('sessions')
            .insert([{ user_id: user.id, metadata: { name: 'New Chat' } }])
            .select();

        if (error) {
            console.error('Error creating new chat:', error);
        } else {
            const newConversation = { id: data[0].id, name: data[0].metadata.name };
            setConversations([newConversation, ...conversations]);
            setActiveConversation(newConversation);
        }
    };

    const deleteConversation = async (id) => {
        const { error } = await supabase.from('sessions').delete().eq('id', id);
        if (error) {
            console.error('Error deleting conversation:', error);
        } else {
            setConversations(conversations.filter(c => c.id !== id));
            if (activeConversation?.id === id) {
                setActiveConversation(null);
            }
        }
    };

    const renameConversation = async (id, newName) => {
        const { error } = await supabase
            .from('sessions')
            .update({ metadata: { name: newName } })
            .eq('id', id);
        
        if (error) {
            console.error('Error renaming conversation:', error);
        } else {
            setConversations(conversations.map(c => c.id === id ? { ...c, name: newName } : c));
        }
    };

    return (
        <div className="w-64 bg-gray-800 text-white flex flex-col p-2">
            <div className="p-2 mb-4">
                <button onClick={createNewChat} className="w-full bg-green-500 hover:bg-green-600 text-white font-bold py-2 px-4 rounded">
                    + New Chat
                </button>
            </div>
            <div className="flex-grow overflow-y-auto">
                {conversations.map(conv => (
                    <div
                        key={conv.id}
                        className={`p-2 my-1 rounded cursor-pointer ${activeConversation?.id === conv.id ? 'bg-gray-700' : 'hover:bg-gray-700'}`}
                        onClick={() => setActiveConversation(conv)}
                    >
                        {conv.name}
                        {/* Add rename/delete buttons here if desired */}
                    </div>
                ))}
            </div>
            <div className="p-2 border-t border-gray-700">
                <button onClick={() => supabase.auth.signOut()} className="w-full bg-red-500 hover:bg-red-600 text-white font-bold py-2 px-4 rounded">
                    Sign Out
                </button>
            </div>
        </div>
    );
};

export default Sidebar;
