const BOARD_SIZE = 15;
const CELL_SIZE = 36;
const BOARD_PADDING = 24;
const STONE_RADIUS = 13;
const CANVAS_SIZE = BOARD_PADDING * 2 + CELL_SIZE * (BOARD_SIZE - 1);

const connectionText = document.getElementById("connection");
const roleText = document.getElementById("role");
const phaseText = document.getElementById("phase");
const readyText = document.getElementById("readyState");
const readyBtn = document.getElementById("readyBtn");
const logBox = document.getElementById("log");
const topBar = document.getElementById("topBar");
const canvas = document.getElementById("board");
const winnerNotice = document.getElementById("winnerNotice");
const ctx = canvas.getContext("2d");

canvas.width = CANVAS_SIZE;
canvas.height = CANVAS_SIZE;

const state = {
  connected: false,
  role: null,
  turn: "black",
  roundActive: false,
  board: createBoard(),
  gameOver: false,
  winner: null,
  ready: {
    black: false,
    white: false
  },
  ws: null
};

function socketUrl() {
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  return `${protocol}//${window.location.host}/ws`;
}

function createBoard() {
  return Array.from({ length: BOARD_SIZE }, () => Array(BOARD_SIZE).fill(null));
}

function isPlayerRole(role) {
  return role === "black" || role === "white";
}

function isInRange(x, y) {
  return x >= 0 && x < BOARD_SIZE && y >= 0 && y < BOARD_SIZE;
}

function roleLabel(role) {
  if (role === "black") return "흑";
  if (role === "white") return "백";
  if (role === "spectator") return "관전자";
  return "-";
}

function turnLabelForMe(turnRole) {
  if (!isPlayerRole(turnRole)) {
    return "-";
  }

  if (isPlayerRole(state.role) && state.role === turnRole) {
    return "내";
  }

  return roleLabel(turnRole);
}

function addLog(kind, text) {
  const row = document.createElement("div");
  row.textContent = `[${kind}] ${text}`;
  logBox.appendChild(row);
  logBox.scrollTop = logBox.scrollHeight;
}

function addMoveLog(role, x, y) {
  addLog("착수", `${roleLabel(role)} (${x},${y}) 착수`);
}

function sendJson(payload) {
  if (!state.ws || state.ws.readyState !== WebSocket.OPEN) {
    return;
  }

  state.ws.send(JSON.stringify(payload));
}

function checkWin(role, x, y) {
  const directions = [
    [1, 0],
    [0, 1],
    [1, 1],
    [1, -1]
  ];

  for (const [dx, dy] of directions) {
    let count = 1;
    count += countDirection(role, x, y, dx, dy);
    count += countDirection(role, x, y, -dx, -dy);
    if (count >= 5) {
      return true;
    }
  }

  return false;
}

function countDirection(role, x, y, dx, dy) {
  let nx = x + dx;
  let ny = y + dy;
  let count = 0;

  while (isInRange(nx, ny) && state.board[ny][nx] === role) {
    count += 1;
    nx += dx;
    ny += dy;
  }

  return count;
}

function applyMove(role, x, y) {
  if (!isPlayerRole(role)) {
    return false;
  }

  if (!isInRange(x, y)) {
    return false;
  }

  if (state.gameOver) {
    return false;
  }

  if (!state.roundActive) {
    return false;
  }

  if (state.turn !== role) {
    return false;
  }

  if (state.board[y][x] !== null) {
    return false;
  }

  state.board[y][x] = role;

  if (checkWin(role, x, y)) {
    state.gameOver = true;
    state.roundActive = false;
    state.winner = role;
    state.ready.black = false;
    state.ready.white = false;
  } else {
    state.turn = role === "black" ? "white" : "black";
  }

  return true;
}

function startRound() {
  state.board = createBoard();
  state.turn = "black";
  state.roundActive = true;
  state.gameOver = false;
  state.winner = null;
  state.ready.black = false;
  state.ready.white = false;
  addLog("접속", "양쪽 준비 완료, 시작");
}

function tryStartRoundByReady() {
  if (!state.ready.black || !state.ready.white) {
    return;
  }

  startRound();
}

function setBoardOutline() {
  canvas.classList.remove("turn-black", "turn-white", "turn-neutral");

  if (!state.connected || !state.roundActive || state.gameOver || !isPlayerRole(state.turn)) {
    canvas.classList.add("turn-neutral");
    return;
  }

  if (state.turn === "black") {
    canvas.classList.add("turn-black");
    return;
  }

  canvas.classList.add("turn-white");
}

function setTopRoleColor() {
  topBar.classList.remove("role-black", "role-white", "role-neutral");

  if (state.role === "black") {
    topBar.classList.add("role-black");
    return;
  }

  if (state.role === "white") {
    topBar.classList.add("role-white");
    return;
  }

  topBar.classList.add("role-neutral");
}

function setWinnerNotice() {
  if (!state.gameOver || !isPlayerRole(state.winner)) {
    winnerNotice.hidden = true;
    winnerNotice.textContent = "";
    return;
  }

  winnerNotice.hidden = false;
  winnerNotice.textContent = `${roleLabel(state.winner)} 승리!`;
}

function updateUi() {
  connectionText.textContent = `연결 상태: ${state.connected ? "연결됨" : "연결 안 됨"}`;
  roleText.textContent = `내 돌 색: ${roleLabel(state.role)}`;
  readyText.textContent = `준비 상태: 흑 ${state.ready.black ? "O" : "X"} | 백 ${state.ready.white ? "O" : "X"}`;

  if (!state.connected) {
    phaseText.textContent = "진행 상태: 연결 대기";
  } else if (state.gameOver) {
    phaseText.textContent = `진행 상태: ${roleLabel(state.winner)} 승리`;
  } else if (!state.roundActive) {
    phaseText.textContent = "진행 상태: 준비 대기";
  } else {
    phaseText.textContent = `진행 상태: ${turnLabelForMe(state.turn)} 차례`;
  }

  const canReady = state.connected &&
    !state.roundActive &&
    isPlayerRole(state.role) &&
    state.ready[state.role] === false;

  readyBtn.disabled = !canReady;

  if (isPlayerRole(state.role) && state.ready[state.role]) {
    readyBtn.textContent = "준비 완료";
  } else {
    readyBtn.textContent = "준비";
  }

  setTopRoleColor();
  setBoardOutline();
  setWinnerNotice();
  drawBoard();
}

function drawBoard() {
  ctx.clearRect(0, 0, CANVAS_SIZE, CANVAS_SIZE);

  ctx.fillStyle = "#d1b17a";
  ctx.fillRect(0, 0, CANVAS_SIZE, CANVAS_SIZE);

  ctx.strokeStyle = "#70532c";
  ctx.lineWidth = 1;

  for (let i = 0; i < BOARD_SIZE; i += 1) {
    const p = BOARD_PADDING + i * CELL_SIZE;

    ctx.beginPath();
    ctx.moveTo(BOARD_PADDING, p);
    ctx.lineTo(CANVAS_SIZE - BOARD_PADDING, p);
    ctx.stroke();

    ctx.beginPath();
    ctx.moveTo(p, BOARD_PADDING);
    ctx.lineTo(p, CANVAS_SIZE - BOARD_PADDING);
    ctx.stroke();
  }

  for (let y = 0; y < BOARD_SIZE; y += 1) {
    for (let x = 0; x < BOARD_SIZE; x += 1) {
      const stone = state.board[y][x];
      if (!stone) {
        continue;
      }

      const cx = BOARD_PADDING + x * CELL_SIZE;
      const cy = BOARD_PADDING + y * CELL_SIZE;

      ctx.beginPath();
      ctx.arc(cx, cy, STONE_RADIUS, 0, Math.PI * 2);
      ctx.fillStyle = stone === "black" ? "#161616" : "#fafafa";
      ctx.fill();
      ctx.strokeStyle = stone === "black" ? "#000000" : "#969696";
      ctx.stroke();
    }
  }
}

function parseMessage(raw) {
  try {
    return JSON.parse(raw);
  } catch (error) {
    return null;
  }
}

function handleMoveMessage(msg) {
  if (!isPlayerRole(msg.role)) {
    return;
  }

  if (state.role === msg.role) {
    return;
  }

  if (typeof msg.x !== "number" || typeof msg.y !== "number") {
    return;
  }

  if (applyMove(msg.role, msg.x, msg.y)) {
    addMoveLog(msg.role, msg.x, msg.y);
    updateUi();
  }
}

function handleReadyMessage(msg) {
  if (!isPlayerRole(msg.role)) {
    return;
  }

  if (typeof msg.ready !== "boolean") {
    return;
  }

  if (state.roundActive) {
    return;
  }

  state.ready[msg.role] = msg.ready;
  tryStartRoundByReady();
  updateUi();
}

function handlePeerEvent(msg) {
  if (msg.event === "join") {
    addLog("접속", `${roleLabel(msg.role)} 입장`);
    return;
  }

  if (msg.event === "leave") {
    if (isPlayerRole(msg.role)) {
      state.roundActive = false;
      state.ready[msg.role] = false;
    }
    addLog("접속", `${roleLabel(msg.role)} 퇴장`);
    updateUi();
  }
}

function handleWelcome(msg) {
  state.role = msg.role;
  addLog("접속", `${roleLabel(msg.role)}로 접속`);
  updateUi();
}

function handleSocketMessage(event) {
  const msg = parseMessage(event.data);
  if (!msg || typeof msg.type !== "string") {
    return;
  }

  if (msg.type === "welcome") {
    handleWelcome(msg);
    return;
  }

  if (msg.type === "peer") {
    handlePeerEvent(msg);
    return;
  }

  if (msg.type === "move") {
    handleMoveMessage(msg);
    return;
  }

  if (msg.type === "ready") {
    handleReadyMessage(msg);
  }
}

function connect() {
  const ws = new WebSocket(socketUrl());
  state.ws = ws;

  ws.onopen = () => {
    state.connected = true;
    state.roundActive = false;
    state.ready.black = false;
    state.ready.white = false;
    addLog("접속", "소켓 연결됨");
    updateUi();
  };

  ws.onmessage = handleSocketMessage;

  ws.onclose = () => {
    state.connected = false;
    state.roundActive = false;
    state.ready.black = false;
    state.ready.white = false;
    addLog("접속", "소켓 연결 종료");
    updateUi();
  };

  ws.onerror = () => {
    addLog("접속", "소켓 오류 발생");
  };
}

function toBoardPosition(clientX, clientY) {
  const rect = canvas.getBoundingClientRect();
  const px = clientX - rect.left;
  const py = clientY - rect.top;

  const gridX = Math.round((px - BOARD_PADDING) / CELL_SIZE);
  const gridY = Math.round((py - BOARD_PADDING) / CELL_SIZE);

  if (!isInRange(gridX, gridY)) {
    return null;
  }

  const snapX = BOARD_PADDING + gridX * CELL_SIZE;
  const snapY = BOARD_PADDING + gridY * CELL_SIZE;
  const maxGap = CELL_SIZE * 0.45;
  if (Math.abs(px - snapX) > maxGap || Math.abs(py - snapY) > maxGap) {
    return null;
  }

  return { x: gridX, y: gridY };
}

canvas.addEventListener("click", (event) => {
  if (!state.connected) {
    return;
  }

  if (!isPlayerRole(state.role)) {
    return;
  }

  if (!state.roundActive || state.gameOver) {
    return;
  }

  if (state.turn !== state.role) {
    return;
  }

  const pos = toBoardPosition(event.clientX, event.clientY);
  if (!pos) {
    return;
  }

  if (!applyMove(state.role, pos.x, pos.y)) {
    return;
  }

  addMoveLog(state.role, pos.x, pos.y);
  sendJson({
    type: "move",
    role: state.role,
    x: pos.x,
    y: pos.y
  });

  updateUi();
});

readyBtn.addEventListener("click", () => {
  if (!state.connected || state.roundActive || !isPlayerRole(state.role)) {
    return;
  }

  if (state.ready[state.role]) {
    return;
  }

  state.ready[state.role] = true;
  sendJson({
    type: "ready",
    role: state.role,
    ready: true
  });

  tryStartRoundByReady();
  updateUi();
});

drawBoard();
updateUi();
connect();
