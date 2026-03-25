const connectionText = document.getElementById("connection");
const roleText = document.getElementById("role");
const messageText = document.getElementById("message");
const canvas = document.getElementById("game");
const ctx = canvas.getContext("2d");

const state = {
  role: null,
  phase: "waiting",
  round: 0,
  world: {
    width: 960,
    height: 540,
    groundY: 500,
    net: { x: 480, width: 20, height: 120 },
    player: { width: 48, height: 60 },
    ballRadius: 14
  },
  players: {
    left: { x: 180, y: 440 },
    right: { x: 732, y: 440 }
  },
  ball: { x: 480, y: 220 },
  remoteInputs: {
    left: { left: false, right: false, jump: false },
    right: { left: false, right: false, jump: false }
  },
  connected: false,
  ws: null,
  notice: "",
  noticeUntil: 0,
  sim: {
    stepMs: 33,
    lastFrameTs: 0,
    accMs: 0
  }
};

const inputState = {
  left: false,
  right: false,
  jump: false
};

let lastSentInput = null;

function socketUrl() {
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  return `${protocol}//${window.location.host}/ws`;
}

function setNotice(text, ms = 1400) {
  state.notice = text;
  state.noticeUntil = performance.now() + ms;
}

function updateStatus() {
  connectionText.textContent = state.connected ? "Connected" : "Disconnected";
  roleText.textContent = `Role: ${state.role || "-"}`;

  if (!state.connected) {
    messageText.textContent = "Socket disconnected";
    return;
  }

  if (state.phase === "waiting") {
    messageText.textContent = "Waiting for opponent";
    return;
  }

  messageText.textContent = `Round: ${state.round}`;
}

function sendInput(force = false) {
  if (!state.ws || state.ws.readyState !== WebSocket.OPEN) {
    return;
  }

  const nextInput = {
    type: "input",
    left: inputState.left,
    right: inputState.right,
    jump: inputState.jump
  };

  if (!force && lastSentInput &&
      lastSentInput.left === nextInput.left &&
      lastSentInput.right === nextInput.right &&
      lastSentInput.jump === nextInput.jump) {
    return;
  }

  state.ws.send(JSON.stringify(nextInput));
  lastSentInput = {
    left: nextInput.left,
    right: nextInput.right,
    jump: nextInput.jump
  };
}

function actionForKey(code) {
  if (code === "ArrowLeft") return "left";
  if (code === "ArrowRight") return "right";
  if (code === "ArrowUp") return "jump";
  return null;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(value, max));
}

function resetPlayersToSpawn() {
  const world = state.world;
  const playerWidth = world.player.width;
  const playerHeight = world.player.height;
  const floorY = world.groundY - playerHeight;

  state.players.left.x = 180;
  state.players.left.y = floorY;
  state.players.left.vx = 0;
  state.players.left.vy = 0;
  state.players.left.onGround = true;

  state.players.right.x = world.width - 180 - playerWidth;
  state.players.right.y = floorY;
  state.players.right.vx = 0;
  state.players.right.vy = 0;
  state.players.right.onGround = true;
}

function ensurePlayerStateShape() {
  for (const role of ["left", "right"]) {
    if (!state.players[role]) {
      state.players[role] = { x: 0, y: 0 };
    }
    if (typeof state.players[role].vx !== "number") state.players[role].vx = 0;
    if (typeof state.players[role].vy !== "number") state.players[role].vy = 0;
    if (typeof state.players[role].onGround !== "boolean") state.players[role].onGround = true;
  }
}

function stepPlayer(body, input, minX, maxX) {
  const world = state.world;
  const gravity = 0.75;
  const speed = 7;
  const jumpSpeed = -13;
  const playerHeight = world.player.height;
  const floorY = world.groundY - playerHeight;

  let dir = 0;
  if (input.left) dir -= 1;
  if (input.right) dir += 1;
  body.vx = dir * speed;

  if (input.jump && body.onGround) {
    body.vy = jumpSpeed;
    body.onGround = false;
  }

  body.vy += gravity;
  body.x += body.vx;
  body.y += body.vy;

  body.x = clamp(body.x, minX, maxX);

  if (body.y >= floorY) {
    body.y = floorY;
    body.vy = 0;
    body.onGround = true;
  } else {
    body.onGround = false;
  }

  if (body.y < 0) {
    body.y = 0;
    if (body.vy < 0) body.vy = 0;
  }
}

function stepPlayersSimulation() {
  if (!state.role) {
    return;
  }

  ensurePlayerStateShape();

  const world = state.world;
  const playerWidth = world.player.width;
  const netLeftEdge = world.net.x - world.net.width / 2;
  const netRightEdge = world.net.x + world.net.width / 2;

  const leftInput = state.role === "left" ? inputState : state.remoteInputs.left;
  const rightInput = state.role === "right" ? inputState : state.remoteInputs.right;

  stepPlayer(state.players.left, leftInput, 0, netLeftEdge - playerWidth);
  stepPlayer(state.players.right, rightInput, netRightEdge, world.width - playerWidth);
}

function onKeyDown(event) {
  const action = actionForKey(event.code);
  if (!action) {
    return;
  }

  if (event.code.startsWith("Arrow")) {
    event.preventDefault();
  }

  if (inputState[action]) {
    return;
  }

  inputState[action] = true;
  sendInput();
}

function onKeyUp(event) {
  const action = actionForKey(event.code);
  if (!action) {
    return;
  }

  if (event.code.startsWith("Arrow")) {
    event.preventDefault();
  }

  if (!inputState[action]) {
    return;
  }

  inputState[action] = false;
  sendInput();
}

function drawBackground() {
  const world = state.world;

  ctx.clearRect(0, 0, canvas.width, canvas.height);

  ctx.fillStyle = "#8dccff";
  ctx.fillRect(0, 0, world.width, world.groundY);

  ctx.fillStyle = "#f6f8ff";
  ctx.fillRect(120, 70, 140, 30);
  ctx.fillRect(520, 50, 170, 32);

  ctx.fillStyle = "#f2cc89";
  ctx.fillRect(0, world.groundY, world.width, world.height - world.groundY);
}

function drawNet() {
  const world = state.world;
  const netLeft = world.net.x - (world.net.width / 2);
  const netTop = world.groundY - world.net.height;

  ctx.fillStyle = "#f2f2f2";
  ctx.fillRect(netLeft, netTop, world.net.width, world.net.height);
  ctx.strokeStyle = "#8498aa";
  ctx.strokeRect(netLeft, netTop, world.net.width, world.net.height);
}

function drawPlayers() {
  const world = state.world;

  const left = state.players.left;
  const right = state.players.right;

  ctx.fillStyle = "#ffd748";
  ctx.fillRect(left.x, left.y, world.player.width, world.player.height);
  ctx.strokeStyle = "#6c5800";
  ctx.strokeRect(left.x, left.y, world.player.width, world.player.height);

  ctx.fillStyle = "#4fa7ff";
  ctx.fillRect(right.x, right.y, world.player.width, world.player.height);
  ctx.strokeStyle = "#0c3f70";
  ctx.strokeRect(right.x, right.y, world.player.width, world.player.height);
}

function drawBall() {
  const ball = state.ball;
  const radius = state.world.ballRadius;

  ctx.beginPath();
  ctx.arc(ball.x, ball.y, radius, 0, Math.PI * 2);
  ctx.fillStyle = "#ffffff";
  ctx.fill();
  ctx.strokeStyle = "#2e2e2e";
  ctx.stroke();
}

function drawOverlay() {
  if (state.phase === "waiting") {
    ctx.fillStyle = "rgba(10, 30, 45, 0.6)";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = "#ffffff";
    ctx.font = "bold 30px Trebuchet MS, sans-serif";
    ctx.textAlign = "center";
    ctx.fillText("Waiting for second player", canvas.width / 2, canvas.height / 2);
  }

  const now = performance.now();
  if (state.notice && now <= state.noticeUntil) {
    ctx.fillStyle = "rgba(12, 29, 39, 0.78)";
    ctx.fillRect(canvas.width / 2 - 180, 24, 360, 44);
    ctx.fillStyle = "#f8fbff";
    ctx.font = "bold 20px Trebuchet MS, sans-serif";
    ctx.textAlign = "center";
    ctx.fillText(state.notice, canvas.width / 2, 54);
  }
}

function render() {
  const now = performance.now();
  const sim = state.sim;
  if (sim.lastFrameTs === 0) {
    sim.lastFrameTs = now;
  }

  const delta = Math.min(100, now - sim.lastFrameTs);
  sim.lastFrameTs = now;
  sim.accMs += delta;

  while (sim.accMs >= sim.stepMs) {
    stepPlayersSimulation();
    sim.accMs -= sim.stepMs;
  }

  drawBackground();
  drawNet();
  drawPlayers();
  drawBall();
  drawOverlay();
  requestAnimationFrame(render);
}

function handleMessage(raw) {
  let payload;
  try {
    payload = JSON.parse(raw);
  } catch {
    return;
  }

  if (payload.type === "welcome") {
    state.role = payload.role || null;
    state.phase = state.role ? "playing" : "waiting";
    if (payload.world) {
      state.world = payload.world;
      canvas.width = state.world.width;
      canvas.height = state.world.height;
    }
    resetPlayersToSpawn();
    updateStatus();
    return;
  }

  if (payload.type === "state") {
    state.phase = payload.phase || "waiting";
    state.round = payload.round || 0;
    if (payload.world) {
      state.world = payload.world;
    }
    if (payload.ball) {
      state.ball = payload.ball;
    }
    updateStatus();
    return;
  }

  if (payload.type === "input_update") {
    const role = payload.role;
    if (role !== "left" && role !== "right") {
      return;
    }
    if (role === state.role) {
      return;
    }

    state.remoteInputs[role] = {
      left: !!payload.left,
      right: !!payload.right,
      jump: !!payload.jump
    };
    if (state.role && state.phase !== "playing") {
      state.phase = "playing";
    }
    updateStatus();
    return;
  }

  if (payload.type === "event") {
    if (payload.name === "round_reset") {
      const winner = payload.winner || "?";
      setNotice(`Rally reset - ${winner} side`);
      resetPlayersToSpawn();
    } else if (payload.name === "peer_left") {
      setNotice("Opponent left");
      state.phase = "waiting";
      state.remoteInputs.left = { left: false, right: false, jump: false };
      state.remoteInputs.right = { left: false, right: false, jump: false };
      resetPlayersToSpawn();
      updateStatus();
    } else if (payload.name === "room_full") {
      setNotice("Room is full", 2200);
      messageText.textContent = "Server has already two players";
    }
  }
}

function connect() {
  const ws = new WebSocket(socketUrl());
  state.ws = ws;

  ws.onopen = () => {
    state.connected = true;
    updateStatus();
    sendInput(true);
  };

  ws.onmessage = (event) => {
    handleMessage(event.data);
  };

  ws.onclose = () => {
    state.connected = false;
    updateStatus();
  };

  ws.onerror = () => {
    setNotice("Socket error", 1800);
  };
}

window.addEventListener("keydown", onKeyDown);
window.addEventListener("keyup", onKeyUp);

updateStatus();
connect();
render();
