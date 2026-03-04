<<<<<<< HEAD
# signalguard-deploy
=======
# SignalGuard Deployment Architecture

This repository centrally manages the container orchestration and routing layer for the **SignalGuard** platform using `docker-compose`.

## Architecture Overview

The platform uses a single edge proxy (NGINX) to handle subdomain routing for both `.local` and `.dev` traffic, ensuring that the development and production topologies remain identical.

| Service | Local Host | Prod Host | Target Container |
|---------|------------|-----------|------------------|
| Marketing Web | `signalguard.local` | `signalguard.dev` | `marketing-web:80` |
| Backend API | `api.signalguard.local` | `api.signalguard.dev` | `backend-api:8000` |
| Platform UX (Hiring) | `hiring.signalguard.local` | `hiring.signalguard.dev` | `platform-ux:80` |
| Platform UX (Admin) | `admin.signalguard.local` | `admin.signalguard.dev` | `platform-ux:80` |
| Platform UX (IDE) | `ide.signalguard.local` | `ide.signalguard.dev` | `platform-ux:80` |
| Platform UX (Replay) | `replay.signalguard.local` | `replay.signalguard.dev` | `platform-ux:80` |
| Platform UX (Auth) | `auth.signalguard.local` | `auth.signalguard.dev` | `platform-ux:80` |

---

## 💻 Local Development Runbook

### Prerequisites

Ensure you have mapped the required local domains to your loopback address in your machine's `/etc/hosts`:

```text
127.0.0.1 signalguard.local
127.0.0.1 api.signalguard.local
127.0.0.1 hiring.signalguard.local
127.0.0.1 admin.signalguard.local
127.0.0.1 ide.signalguard.local
127.0.0.1 replay.signalguard.local
127.0.0.1 auth.signalguard.local
```

### Start Local Services

The development configuration maps source code locally from adjacent repository folders (`../signalguard-backend`, `../signalguard-ux`, etc.).

1. Navigate to this repository:
   ```bash
   cd signalguard-deploy
   ```

2. Build and run all services in the background:
   ```bash
   docker-compose up --build -d
   ```

3. View live logs:
   ```bash
   # Follow all logs
   docker-compose logs -f
   
   # Or a specific service
   docker-compose logs -f backend-api
   ```

4. Stop local environment:
   ```bash
   docker-compose down
   ```

---

## 🚀 Production Deployment Runbook

The production configuration uses pre-built images from GitHub Container Registry (`ghcr.io/signalguard/*`) and applies strict resource constraints. It **does not** build images from source.

1. Start all production services:
   ```bash
   docker-compose -f docker-compose.prod.yml up -d
   ```

2. Validate active containers and network topology:
   ```bash
   docker-compose -f docker-compose.prod.yml ps
   ```

3. Apply a rolling restart to update a specific service to latest GHCR image:
   ```bash
   docker-compose -f docker-compose.prod.yml pull backend-api
   docker-compose -f docker-compose.prod.yml up -d --no-deps backend-api
   ```

---

## Repository Structure

- `docker-compose.yml`: Local develop orchestration with live code-mounts.
- `docker-compose.prod.yml`: Production orchestration locked to GHCR images.
- `nginx/`: NGINX proxy configs, headers, TLS rules, and subdomain routing.
>>>>>>> 6368eae (feat(deploy): Initial multi-repo deployment orchestration layout)
