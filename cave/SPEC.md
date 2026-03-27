# Cave Socket Test MVP Spec

## 1. Overview

This directory contains a minimal online socket test game.

- Runtime server: PowerShell (`server.ps1`)
- Worker module: PowerShell module (`worker.psm1`)
- Client: static HTML/CSS/JavaScript only
- Transport: WebSocket (`/ws`)
- Game rules authority: frontend only
- Local self-play page: `/self.html`

## 2. Scope

Included:

- Single room
- 15x15 free-rule board game
- Role assignment for first two players (`black`, `white`)
- Spectator join support
- Ready handshake required before first start and each restart
- Local self-play mode on single screen (`/self.html`)

Excluded:

- Server-side move validation and winner check
- Reconnect recovery and board state replay
- Multi-room support
- Auth and persistence

## 3. Server Contract

HTTP routes:

- `GET /` -> `index.html`
- `GET /index.html`
- `GET /script.js`
- `GET /self.html`
- `GET /self.js`
- `GET /style.css`
- `GET /ws` (WebSocket upgrade endpoint)

Runtime:

- Listener prefix: `http://+:4608/`
- Server only relays client text messages to connected clients
- Server sends system messages (`welcome`, `peer`)

Role assignment:

- Current player roles are checked from connected sockets
- If no players exist: first player role is randomly assigned (`black` or `white`)
- If one player exists: next player gets remaining role
- If both roles exist: new client is `spectator`

## 4. WebSocket Messages

Server -> Client:

```json
{
  "type": "welcome",
  "role": "black"
}
```

```json
{
  "type": "peer",
  "event": "join",
  "role": "white"
}
```

```json
{
  "type": "peer",
  "event": "leave",
  "role": "black"
}
```

Client -> Server (relay message):

```json
{
  "type": "move",
  "role": "black",
  "x": 7,
  "y": 7
}
```

```json
{
  "type": "ready",
  "role": "white",
  "ready": true
}
```

Rules:

- Server does not validate move order, board occupancy, or winner state
- Frontend enforces turn and winner rules
- Frontend starts and restarts a round only when both `black` and `white` are `ready: true`

## 5. Gameplay Rules (Frontend)

- Board size: 15x15
- Players alternate turns (`black` first)
- Five in a row wins (horizontal, vertical, diagonal)
- Free rule only (no forbidden move checks)
- Spectator cannot place stones or set ready

Self-play mode (`/self.html`):

- Uses same 15x15 free-rule board and winner check logic
- No WebSocket gameplay sync is used
- Black/white stones are placed alternately on one screen
- Next round starts by button click (`다음 판 시작`)

## 6. UI Rules (Frontend)

- Left `aside` shows connection logs and move logs.
- Board outline uses high-contrast style and shows current turn (`black` or `white`).
- Top area shows connection status, ready status, and my stone color.
- Top menu color also reflects my stone color (`black`, `white`, `neutral`).
- Page background uses a gray tone.
- When game ends, a large winner notice is shown over the board.
- Korean UI text is used.

## 7. Assumptions

- Trusted internal environment (minimal validation)
- Late spectator does not receive full historical board replay
- Current game state sync is based on messages received after connection
