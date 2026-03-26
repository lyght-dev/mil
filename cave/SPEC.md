# Cave Omok MVP Spec

## 1. Overview

This directory contains a minimal online omok game.

- Runtime server: PowerShell (`server.ps1`)
- Worker module: PowerShell module (`worker.psm1`)
- Client: static HTML/CSS/JavaScript only
- Transport: WebSocket (`/ws`)
- Game rules authority: frontend only

## 2. Scope

Included:

- Single room
- 15x15 free-rule omok
- Role assignment for first two players (`black`, `white`)
- Spectator join support
- Manual restart after win (`ready`)

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
- Frontend restarts a round only when both `black` and `white` are `ready: true`

## 5. Gameplay Rules (Frontend)

- Board size: 15x15
- Players alternate turns (`black` first)
- Five in a row wins (horizontal, vertical, diagonal)
- Free rule only (no forbidden move checks)
- Spectator cannot place stones or set ready

## 6. Assumptions

- Trusted internal environment (minimal validation)
- Late spectator does not receive full historical board replay
- Current game state sync is based on messages received after connection
