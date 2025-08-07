import http from 'k6/http';
import { check, sleep } from 'k6';

// This is a basic load test for the main API endpoint.
//
// Prerequisites:
//   - k6 must be installed: https://k6.io/docs/getting-started/installation/
//
// Usage:
//   k6 run scripts/load_test.js
//
// You can configure the target URL and load parameters below.

export const options = {
  // Simulate 10 virtual users
  vus: 10,
  // For a duration of 30 seconds
  duration: '30s',
};

// The target URL for the API.
// IMPORTANT: You must have a valid JWT for this to work, as the endpoint is protected.
// You can get a token by logging in through the UI and inspecting the network requests.
const API_URL = 'https://api.your-domain.com/chat';
const JWT_TOKEN = 'paste_your_valid_jwt_here';

export default function () {
  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${JWT_TOKEN}`,
  };

  const payload = JSON.stringify({
    message: 'What are the latest AI trends?',
  });

  const res = http.post(API_URL, payload, { headers });

  // Check if the request was successful (status code 200)
  check(res, {
    'is status 200': (r) => r.status === 200,
  });

  sleep(1); // Wait for 1 second between requests
}
