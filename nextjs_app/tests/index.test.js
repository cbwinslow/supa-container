import React from 'react';
import { render, screen } from '@testing-library/react';
import Home from '../pages/index';
import '@testing-library/jest-dom';

// Mock Supabase hooks
jest.mock('@supabase/auth-helpers-react', () => ({
  useSession: () => null, // Mock that the user is not logged in
  useSupabaseClient: () => ({}),
}));

describe('Home Page', () => {
  it('renders the login page when no session is active', () => {
    render(<Home />);
    
    // Check for a key element of the login UI
    expect(screen.getByText('Welcome to the RAG Platform')).toBeInTheDocument();
  });
});
