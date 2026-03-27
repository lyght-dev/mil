function closeOnlineSocketForSelfMode() {
  if (!state.ws) {
    return;
  }

  state.ws.onopen = null;
  state.ws.onmessage = null;
  state.ws.onclose = null;
  state.ws.onerror = null;

  if (state.ws.readyState === WebSocket.OPEN || state.ws.readyState === WebSocket.CONNECTING) {
    state.ws.close();
  }

  state.ws = null;
}

function syncSelfUi() {
  updateUi();
  connectionText.textContent = "연결 상태: 로컬 자기대국";
  roleText.textContent = "내 돌 색: 흑/백 순차 진행";

  if (state.gameOver) {
    readyText.textContent = "자기대국: 종료";
    readyBtn.textContent = "다음 판 시작";
    readyBtn.disabled = false;
    return;
  }

  if (!state.roundActive) {
    readyText.textContent = "자기대국: 대기";
    readyBtn.textContent = "다음 판 시작";
    readyBtn.disabled = false;
    return;
  }

  readyText.textContent = "자기대국: 진행 중";
  readyBtn.textContent = "진행 중";
  readyBtn.disabled = true;
}

function startSelfRound() {
  state.board = createBoard();
  state.turn = "black";
  state.roundActive = true;
  state.gameOver = false;
  state.winner = null;
  state.ready.black = false;
  state.ready.white = false;
  addLog("자가", "다음 판 시작");
  syncSelfUi();
}

function initSelfMode() {
  closeOnlineSocketForSelfMode();

  state.connected = true;
  state.role = "spectator";
  state.ready.black = false;
  state.ready.white = false;

  logBox.innerHTML = "";
  addLog("자가", "로컬 자기대국 모드");

  startSelfRound();
}

canvas.addEventListener("click", (event) => {
  if (!state.roundActive || state.gameOver) {
    return;
  }

  const pos = toBoardPosition(event.clientX, event.clientY);
  if (!pos) {
    return;
  }

  const currentTurn = state.turn;
  if (!applyMove(currentTurn, pos.x, pos.y)) {
    return;
  }

  addMoveLog(currentTurn, pos.x, pos.y);
  syncSelfUi();
});

readyBtn.addEventListener("click", () => {
  if (state.roundActive && !state.gameOver) {
    return;
  }

  startSelfRound();
});

initSelfMode();
