import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import Home from '../pages/index';
import Dashboard from '../pages/dashboard';
import '@testing-library/jest-dom';

// --- Mocks ---
// Mock Supabase hooks for all tests in this file
jest.mock('@supabase/auth-helpers-react', () => {
  const originalModule = jest.requireActual('@supabase/auth-helpers-react');
  return {
    ...originalModule,
    useSession: jest.fn(),
    useSupabaseClient: jest.fn(() => ({
      auth: {
        signOut: jest.fn(),
        getSession: jest.fn(() => Promise.resolve({ data: { session: { access_token: 'fake-token' } } })),
      },
      from: jest.fn(() => ({
        select: jest.fn(() => ({
          eq: jest.fn(() => ({
            order: jest.fn(() => ({ data: [], error: null })),
          })),
        })),
      })),
    })),
  };
});

// Mock the Message component as it's a presentational detail
jest.mock('../components/Message', () => () => <div data-testid="message"></div>);

const { useSession } = require('@supabase/auth-helpers-react');

// --- Tests ---

describe('Home Page', () => {
  it('renders the login UI when no session is active', () => {
    useSession.mockReturnValue(null);
    render(<Home />);
    expect(screen.getByText('Welcome to the RAG Platform')).toBeInTheDocument();
  });

  it('renders the Dashboard when a session is active', () => {
    useSession.mockReturnValue({ user: { id: '123' } }); // Mock an active session
    render(<Home />);
    expect(screen.getByText('Agentic RAG Dashboard')).toBeInTheDocument();
  });
});

describe('Dashboard Component', () => {
  beforeEach(() => {
    // Mock fetch for the models API call
    global.fetch = jest.fn(() =>
      Promise.resolve({
        json: () => Promise.resolve({ data: [{ id: 'gpt-4' }] }),
      })
    );
    useSession.mockReturnValue({ user: { id: '123' } });
  });

  it('renders the main components of the dashboard', () => {
    render(<Dashboard />);
    expect(screen.getByText('Agentic RAG Dashboard')).toBeInTheDocument();
    expect(screen.getByText('1. Ingest PDF Document')).toBeInTheDocument();
    expect(screen.getByText('2. Query Your Documents')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Ask the agent anything...')).toBeInTheDocument();
  });

  it('enables the Send button only when there is a query', () => {
    render(<Dashboard />);
    const sendButton = screen.getByRole('button', { name: 'Send' });
    const queryInput = screen.getByPlaceholderText('Ask the agent anything...');

    expect(sendButton).toBeDisabled();
    fireEvent.change(queryInput, { target: { value: 'Hello' } });
    expect(sendButton).toBeEnabled();
  });

  it('adds user message to the chat on send', () => {
    render(<Dashboard />);
    const queryInput = screen.getByPlaceholderText('Ask the agent anything...');
    const sendButton = screen.getByRole('button', { name: 'Send' });

    fireEvent.change(queryInput, { target: { value: 'Test query' } });
    fireEvent.click(sendButton);

    // The mock Message component will be rendered
    // We expect two messages: one for the user, one for the initial assistant response
    const messages = screen.getAllByTestId('message');
    expect(messages.length).toBe(2);
  });
});