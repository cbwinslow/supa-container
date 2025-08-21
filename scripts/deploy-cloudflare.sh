#!/usr/bin/env bash
set -e

# Build the Next.js app
npm --prefix frontend run build

# Deploy using Cloudflare Wrangler
npx wrangler pages deploy frontend/.next --project-name=political-document-analyzer
