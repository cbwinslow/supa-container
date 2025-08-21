import "@testing-library/jest-dom";
import { render } from "@testing-library/react";
import Home from "../pages/index";

jest.mock("../lib/supabaseClient", () => ({
  supabase: {
    auth: {
      getSession: jest.fn().mockResolvedValue({ data: { session: null } }),
      signInWithOAuth: jest.fn(),
    },
  },
}));

test("shows login button when no session", async () => {
  const { findByText } = render(<Home />);
  expect(await findByText(/Login with GitHub/i)).toBeInTheDocument();
});
