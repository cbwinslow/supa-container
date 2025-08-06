# --- Base Stage ---
# Get the smallest possible node image
FROM node:18-alpine AS base

# --- Dependencies Stage ---
# Install dependencies first, in a separate step to leverage Docker's caching.
FROM base AS deps
WORKDIR /app
COPY package.json ./
# Use npm ci for reproducible builds if a lockfile is present, otherwise use install
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi

# --- Builder Stage ---
# Build the Next.js application
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

# --- Runner Stage ---
# The final, small image that will run the application
FROM base AS runner
WORKDIR /app
# Copy only the necessary artifacts from the builder stage
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json

EXPOSE 3000
CMD ["npm", "start"]