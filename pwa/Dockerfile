# syntax=docker/dockerfile:1.6

# ─── Stage 1: Build ───────────────────────────────────────────────────────────
FROM node:20-alpine AS builder
WORKDIR /app

# Copy lockfile and manifest first for better layer caching
COPY pwa/package.json pwa/package-lock.json ./
RUN npm ci

# Copy source and build
COPY pwa/ ./
ARG VITE_QR_ENCRYPTION_KEY
ENV VITE_QR_ENCRYPTION_KEY=$VITE_QR_ENCRYPTION_KEY
RUN npm run build

# ─── Stage 2: Serve ───────────────────────────────────────────────────────────
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY pwa/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
