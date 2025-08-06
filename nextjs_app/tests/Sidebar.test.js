import React from 'react';
import { render, screen } from '@testing-library/react';
import Sidebar from '../components/Sidebar';
import '@testing-library/jest-dom';

// Mock Supabase hooks
jest.mock('@supabase/auth-helpers-react', () => ({
  useUser: () => ({ id: '123' }),
  useSupabaseClient: () => ({
    from: () => ({
      select: () => ({
        eq: () => ({
          order: () => ({
            data: [
              { id: 'conv1', metadata: { name: 'Conversation 1' }, created_at: new Date().toISOString() },
              { id: 'conv2', metadata: { name: 'Conversation 2' }, created_at: new Date().toISOString() },
            ],
            error: null,
          }),
        }),
      }),
    }),
  }),
}));

describe('Sidebar Component', () => {
  it('renders a list of conversations', async () => {
    const conversations = [
      { id: 'conv1', name: 'Conversation 1' },
      { id: 'conv2', name: 'Conversation 2' },
    ];
    const setConversations = jest.fn();

    render(<Sidebar conversations={conversations} setConversations={setConversations} />);

    // Use findByText for async operations if data loading were real
    expect(await screen.findByText('Conversation 1')).toBeInTheDocument();
    expect(await screen.findByText('Conversation 2')).toBeInTheDocument();
  });

  it('highlights the active conversation', () => {
    const conversations = [{ id: 'conv1', name: 'Conversation 1' }];
    const activeConversation = { id: 'conv1', name: 'Conversation 1' };
    render(<Sidebar conversations={conversations} activeConversation={activeConversation} />);
    
    const convoElement = screen.getByText('Conversation 1');
    // Check for a class that indicates it's active
    expect(convoElement).toHaveClass('bg-gray-700');
  });
});
