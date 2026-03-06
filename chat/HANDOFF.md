# Handoff

## 2026-03-06

- Implemented chat backend in `server.ps1`:
  - Added `HttpListener` server on configurable host/port (default `localhost:9999`).
  - Implemented long polling API endpoints:
    - `POST /join`
    - `POST /send`
    - `GET /poll`
    - `POST /leave`
    - `GET /health`
  - Added JSON error contract with status codes `400/401/404/405/500`.
  - Added CORS headers and `OPTIONS` handling (`204`).
  - Added concurrent request processing using worker runspaces + blocking request queue.
  - Added per-client pending message queues and wake signals for long-poll completion.
  - Added idle client cleanup (default 5 minutes) with resource disposal.

- Implemented console client in `client.ps1`:
  - Prompts for name at startup and validates 1~20 length.
  - Calls `/join`, then starts background poll loop (`/poll`) for incoming messages.
  - Sends typed lines via `/send`.
  - Supports `/exit` command to call `/leave` and stop cleanly.
  - Displays messages as `[HH:mm:ss] senderName: text`.

- Added `SPEC.md` for `/chat`:
  - Captures architecture, API schema, constraints, validation, error model, and test scenarios.
  - Documents run commands for server/client.

- Notes:
  - Message delivery policy is "new messages only" (no full history replay).
  - Name duplication is allowed; server identity is `clientId`.

## 2026-03-06 (simplification pass)

- Refactored for lightweight internal-LAN usage:
  - Replaced complex per-client queue/signal architecture with a simple global recent-message buffer (`MaxMessages`, default 200).
  - Polling now uses cursor (`id > cursor`) scan + short sleep loop until timeout.
  - Kept same core endpoints (`/join`, `/send`, `/poll`, `/leave`, `/health`) to avoid client/server contract breakage.
  - Reduced server complexity while retaining concurrent handling through a runspace pool.

- Updated client to match simplified behavior:
  - Maintains only one cursor value.
  - Background poll loop prints incoming messages and advances cursor.
  - Main loop sends plain text and exits via `/exit`.

- Updated `SPEC.md`:
  - Rewritten as "Simple LAN Chat" spec focused on non-critical network-check usage.
  - Added explicit LAN run examples using server host IP.

- Added simple tick/tock utility scripts in `/chat`:
  - `tiktok-server.ps1`: lightweight HTTP server (`POST /tiktok`) returning `tock` when request body is `tick`.
  - `tiktok-clinet.ps1`: tiny client that posts `tick` and prints server response.
  - Purpose: quick internal network connectivity verification, independent from main chat flow.

- Added SSE smoke-test utilities in `/chat`:
  - `tiktok-stream-server.ps1`: minimal SSE server with `GET /stream`, `POST /tick`, and `GET /health`.
  - Server keeps only active stream connections in memory and broadcasts `event: tock` / `data: tock` frames on each valid tick.
  - `tiktok-stream-client.ps1`: connects to `/stream`, optionally sends one tick via `-SendTick`, and prints the first event received.
  - Intended to validate the HTTP-only streaming approach before refactoring main chat to SSE.
