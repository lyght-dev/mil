# BB Number Baseball MVP Spec

## Overview

- Client-only static game in `bb/`
- Runtime server: PowerShell with `milkit.psm1`
- Files: `index.html`, `style.css`, `script.js`, `server.ps1`
- One human vs one computer

## Server

- `server.ps1` imports `../milkit/milkit.psm1`
- Static root is `bb/`
- `GET /` serves `index.html`
- `GET /index.html`
- `GET /style.css`
- `GET /script.js`
- `GET /health` returns `{ "status": "ok" }`

## Rules

- Intro screen lets the player choose difficulty `1`, `2`, or `3`
- The player then enters a 4-digit secret number
- Digits use `0-9`
- Digits cannot repeat
- Computer secret also uses 4 distinct digits
- Difficulty changes both computer response delay and guess algorithm
  - `1`: `1400ms`
  - `2`: `900ms`
  - `3`: `500ms`
- Difficulty algorithms
  - `1`: fully random valid 4-digit guesses
  - `2`: random guess from remaining candidates after filtering by previous feedback
  - `3`: Knuth-style candidate search using prebuilt feedback table and sampled minimax choice

## Screen Layout

- Top-left: 4 gray hidden blocks for the computer secret, each showing `?`
- Top-left blocks are clickable memo cards; each slot accepts one local digit memo and shows that digit instead of `?`
- Bottom-right: 4 white blocks showing the player's secret digits
- Center: turn/status text and split log area
- Log header includes a computer-log toggle; default is on
- During computer turn delay, the log panel shows a visible fallback notice that the computer is thinking
- Guess logs are rendered in two half-width columns: player on the left, computer on the right
- Start/status/end text logs stay in a separate full-width event area above the split columns
- Player turn input: 4-digit text input and submit button

## Turn Flow

1. Player submits a 4-digit guess
2. App shows strike/ball count and appends it to the center log
3. Computer waits by difficulty delay, then makes a random valid 4-digit guess
4. App shows computer strike/ball count in the same log
5. Turn returns to the player

## Round End

- If the player gets `4S`, the game does not end immediately
- The computer still takes its matching turn once
- After that round:
  - player only got `4S` -> player win
  - computer only got `4S` -> computer win
  - both got `4S` -> draw
- If nobody gets `4S`, play continues

## Out of Scope

- Smart computer deduction
- Turn limits
- Scoreboard
- Save/load
- Duplicate-guess blocking
