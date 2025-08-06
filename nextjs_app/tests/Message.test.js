import React from 'react';
import { render, screen } from '@testing-library/react';
import Message from '../components/Message';
import '@testing-library/jest-dom';

describe('Message Component', () => {
  it('renders a user message with simple text', () => {
    const message = { role: 'user', content: 'Hello, AI!' };
    render(<Message message={message} />);
    expect(screen.getByText('Hello, AI!')).toBeInTheDocument();
    expect(screen.getByText('You')).toBeInTheDocument();
  });

  it('renders an AI message with markdown', () => {
    const message = { role: 'assistant', content: '**Bold text** and `code`' };
    render(<Message message={message} />);
    
    // Check for the rendered HTML elements
    const boldElement = screen.getByText('Bold text');
    expect(boldElement.tagName).toBe('STRONG');
    
    const codeElement = screen.getByText('code');
    expect(codeElement.tagName).toBe('CODE');
  });

  it('renders a code block with syntax highlighting', () => {
    const message = {
      role: 'assistant',
      content: '```python\nprint("Hello, World!")\n```',
    };
    render(<Message message={message} />);
    
    // react-syntax-highlighter renders the code in a specific structure
    const codeElement = screen.getByText('print("Hello, World!")');
    expect(codeElement).toBeInTheDocument();
    // Check for a class applied by the syntax highlighter
    expect(codeElement.closest('pre')).toHaveClass('prism-code');
  });
});
