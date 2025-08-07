const { test, expect } = require('@playwright/test');

// --- Test Configuration ---
// We will pull credentials from environment variables for security.
// In a CI/CD environment, you would set these as secrets.
const TEST_USER_EMAIL = process.env.E2E_TEST_USER_EMAIL || 'test@example.com';
const TEST_USER_PASSWORD = process.env.E2E_TEST_USER_PASSWORD || 'password123';
const APP_URL = process.env.E2E_APP_URL || 'http://localhost:3000';

test.describe('Real End-to-End Chat Flow', () => {

  // Before each test, we will perform a login.
  test.beforeEach(async ({ page }) => {
    await page.goto(APP_URL);

    // Check if we are already on the dashboard (e.g., from a previous run)
    const dashboardVisible = await page.isVisible('text=Agentic RAG Dashboard');
    if (dashboardVisible) {
      return; // Already logged in
    }

    // If not, perform the login flow
    await expect(page.getByText('Welcome to the RAG Platform')).toBeVisible();

    // Fill in the email and password
    await page.getByPlaceholder('Your email address').fill(TEST_USER_EMAIL);
    await page.getByPlaceholder('Your password').fill(TEST_USER_PASSWORD);

    // Click the sign-in button
    await page.getByRole('button', { name: 'Sign in' }).click();

    // Wait for the navigation to the dashboard to complete
    await expect(page.getByText('Agentic RAG Dashboard')).toBeVisible({ timeout: 10000 });
  });

  test('should allow a logged-in user to send a message and receive a streamed response', async ({ page }) => {
    // We are now on the dashboard page after the beforeEach hook.

    // Find the chat input and send button
    const chatInput = page.getByPlaceholder('Ask the agent anything...');
    const sendButton = page.getByRole('button', { name: 'Send' });

    // Type a message and click send
    const userMessage = 'What are the main differences between vector search and graph search?';
    await chatInput.fill(userMessage);
    await sendButton.click();

    // 1. Assert that the user's message appears immediately in the chat history
    await expect(page.getByText(userMessage)).toBeVisible();

    // 2. Assert that the AI's response area appears and contains the streamed response.
    // We will wait for a keyword that is likely to appear in the final response.
    // This is a robust way to test streaming.
    // Note: This requires the backend to be running and responsive.
    await expect(page.getByText('semantic similarity', { exact: false })).toBeVisible({ timeout: 20000 });
    await expect(page.getByText('relationships between entities', { exact: false })).toBeVisible({ timeout: 20000 });

    // 3. (Optional) Assert that the "Tools Used" section appears
    await expect(page.getByText('Tools Used:')).toBeVisible();
  });
});