# Volleyball MVP Spec

## 1. Overview

This directory contains a minimal 2-player online volleyball game.

- Runtime server: PowerShell (`server.ps1`)
- Client: static HTML/CSS/JavaScript only
- Transport: WebSocket for realtime gameplay (`/ws`)
- Rendering: simple geometric shapes only (no sprite assets in MVP)

## 2. Scope

Included:

- Single room only
- Max 2 players (`left`, `right`)
- Server-authoritative simulation
- Keyboard input only
- Basic movement, jump, collisions, rally reset

Excluded:

- Multi-room
- Spectator mode
- Match score / set system
- Mobile controls
- Auth, persistence, reconnect recovery

## 3. Server Contract

HTTP routes:

- `GET /` -> `index.html`
- `GET /index.html`
- `GET /script.js`
- `GET /style.css`
- `GET /ws` (WebSocket upgrade endpoint)

WebSocket behavior:

- First two clients get assigned roles (`left`, `right`)
- Third and later clients receive `room_full` event and are disconnected
- No periodic `state` stream in current mode
- Server broadcasts `input_update` only when a player's input changes
- Server broadcasts `ball_update` at fixed interval for ball position sync

## 4. WebSocket Messages

Client -> Server:

```json
{
  "type": "input",
  "left": true,
  "right": false,
  "jump": false
}
```

Server -> Client:

```json
{
  "type": "welcome",
  "role": "left",
  "world": {}
}
```

```json
{
  "type": "event",
  "name": "round_reset",
  "winner": "left"
}
```

```json
{
  "type": "input_update",
  "role": "left",
  "left": false,
  "right": true,
  "jump": false
}
```

```json
{
  "type": "ball_update",
  "phase": "playing",
  "round": 12,
  "ball": {
    "x": 523.0,
    "y": 214.5,
    "vx": 3.2,
    "vy": -1.75
  }
}
```

Possible `event.name` values:

- `round_reset`
- `peer_left`
- `room_full`

`input_update` rule:

- Sent only when a player's input actually changes.
- Client ignores `input_update` whose `role` is equal to its own role.

`ball_update` rule:

- Sent by server at fixed interval (current: ~15Hz).
- Client uses it to update ball position and match phase/round display.

## 5. Gameplay Rules (MVP)

- Left player movement area: left half of court
- Right player movement area: right half of court
- Ball and players collide with walls / ground / net / each other
- When the ball touches ground, no score is tracked
- Round resets immediately and play continues
