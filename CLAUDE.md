# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Immich is a high-performance self-hosted photo and video management solution organized as a monorepo with multiple distinct components.

## Repository Structure

- `server/` - Backend API (Node.js/NestJS/TypeScript)
- `web/` - Web frontend (Svelte 5/SvelteKit/TypeScript)
- `mobile/` - Flutter mobile application (iOS/Android/Dart)
- `machine-learning/` - Python ML service for CLIP embeddings, facial recognition, OCR
- `cli/` - Command-line interface (TypeScript)
- `open-api/` - OpenAPI specification and SDK generation
- `docs/` - Docusaurus documentation
- `e2e/` - End-to-end testing with Playwright
- `plugins/` - Plugin system for extensibility
- `i18n/` - Internationalization translations

## Technology Stack

| Component       | Technology                                    |
|-----------------|-----------------------------------------------|
| Backend         | Node.js 24, NestJS, TypeScript, PostgreSQL, Kysely, Redis/Valkey, BullMQ, Socket.IO |
| Web             | Svelte 5, SvelteKit, TypeScript, TailwindCSS v4, MapLibre GL |
| Mobile          | Flutter, Dart, Riverpod, Drift, Isar         |
| Machine Learning| Python 3.11+, FastAPI, HuggingFace Hub, ONNX Runtime, InsightFace, CLIP |
| Infrastructure  | Docker, Docker Compose, pnpm, uv, Make, mise |

## Common Commands

All development commands are available via Makefile at the root:

### Development with Docker
```bash
make dev              # Start development docker compose
make dev-down         # Stop development containers
make dev-update       # Rebuild and start dev containers
make dev-scale        # Scale server to 3 instances for testing
make prod             # Start production docker compose
make prod-down        # Stop production containers
```

### Install Dependencies
```bash
make install-all               # Install all dependencies (excluding docs)
make install-<module>          # Install dependencies for specific module (cli/server/web etc.)
```

### Building
```bash
make build-all                 # Build all modules (excluding e2e, docs)
make build-<module>            # Build specific module
```

### Code Quality
```bash
make check-all       # Run all type checks
make lint-all        # Run all lint fixes
make format-all      # Format all code
make hygiene-all     # Run audit, format, check, sql
make check-<module>  # Type check specific module
make lint-<module>   # Lint fix specific module
make format-<module> # Format specific module
```

### Testing
```bash
make test-all        # Run all tests
make test-<module>   # Run tests for specific module (server/web/cli)
make test-e2e        # Run end-to-end tests
make test-medium     # Run medium-complexity tests in Docker
```

### Code Generation
```bash
make open-api         # Generate OpenAPI specs for both Dart and TypeScript
make open-api-dart    # Generate Dart client SDK (for mobile)
make open-api-typescript # Generate TypeScript client SDK (for web/cli)
make sql              # Sync SQL schema with Kysely
```

### Utility
```bash
make clean           # Clean all node_modules, dist, and build artifacts
make attach-server   # Attach shell to running server container
```

### Per-module development (JavaScript/TypeScript)
From within module directory:
```bash
pnpm run build        # Build production output
pnpm run dev          # Start development server
pnpm run lint:fix     # Fix lint issues
pnpm run format:fix   # Fix formatting
pnpm run check        # Type checking
pnpm run test         # Run unit tests
```

### Machine Learning development (Python)
Uses `uv` for dependency management:
```bash
uv sync --extra cpu/cuda/rocm/openvino  # Install dependencies
uv run pytest                            # Run tests
```

## Architecture

### Backend (server/)
- REST API built with NestJS
- PostgreSQL with pgvector and vectorchord extensions for vector search
- Kysely query builder (migrated from TypeORM)
- BullMQ for background job processing
- Redis/Valkey for caching and pub/sub
- Socket.IO for WebSocket connections
- Key structure:
  - `src/controllers/` - REST API endpoints
  - `src/services/` - Business logic
  - `src/repositories/` - Data access layer
  - `src/workers/` - Background job processing
  - `src/schema/` - Database schema

### Web Frontend (web/)
- Svelte 5 with SvelteKit, static adapter (completely static output)
- TailwindCSS v4 for styling
- Uses generated `@immich/sdk` for API access
- Key structure:
  - `src/routes/` - SvelteKit routes
  - `src/lib/components/` - Reusable UI components
  - `src/lib/stores/` - State management
  - `src/lib/services/` - API service layer

### Mobile (mobile/)
- Flutter application for iOS/Android
- Riverpod for state management
- Drift for local persistent cache
- AutoRoute for navigation
- Generated OpenAPI client from main spec
- Clean architecture with domain/presentation/infrastructure layers

### Machine Learning (machine-learning/)
- FastAPI application
- Provides: CLIP semantic image embeddings, facial recognition, OCR text extraction
- Model caching via huggingface-hub
- Multiple hardware acceleration options (CPU, CUDA, ROCM, OpenVINO, etc.)

## Infrastructure

- **Docker Compose** is used for both development and production deployment
- Production services: `immich-server`, `immich-machine-learning`, `redis`, `postgresql`
- OpenAPI specification at `open-api/immich-openapi-specs.json` generates client SDKs automatically
- pnpm workspace manages all JavaScript/TypeScript packages
- mise handles tool version management (node, flutter, pnpm)

## Key Features

- Automatic photo/video backup from mobile devices
- Duplicate detection and prevention
- Search by metadata, objects, faces, and CLIP (semantic search)
- Facial recognition and clustering
- Maps integration (view photos on map based on GPS data)
- Multi-user support, albums, shared albums, partner sharing
- OAuth support, API keys
- RAW format support, Live Photo, 360° photos
- Tags, folder view, archive, favorites, memories ("on this day")
- Public sharing, custom storage structure
- Offline support (mobile)
