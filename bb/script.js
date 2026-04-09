const COMPUTER_DELAYS = {
  1: 1400,
  2: 900,
  3: 500
};
const LEVEL3_SAMPLE_SIZE = 200;

let allCandidatesCache = null;
let feedbackTableCache = null;

const introScreen = document.getElementById("introScreen");
const gameScreen = document.getElementById("gameScreen");
const setupForm = document.getElementById("setupForm");
const playerSecretInput = document.getElementById("playerSecretInput");
const setupMessage = document.getElementById("setupMessage");
const statusText = document.getElementById("statusText");
const difficultyText = document.getElementById("difficultyText");
const resultText = document.getElementById("resultText");
const turnText = document.getElementById("turnText");
const computerSecretSlots = document.getElementById("computerSecretSlots");
const playerSecretSlots = document.getElementById("playerSecretSlots");
const eventLogBox = document.getElementById("eventLogBox");
const playerLogBox = document.getElementById("playerLogBox");
const computerLogBox = document.getElementById("computerLogBox");
const computerLogToggle = document.getElementById("computerLogToggle");
const thinkingNotice = document.getElementById("thinkingNotice");
const guessForm = document.getElementById("guessForm");
const guessInput = document.getElementById("guessInput");
const guessButton = document.getElementById("guessButton");
const guessMessage = document.getElementById("guessMessage");
const restartButton = document.getElementById("restartButton");

const state = {
  screen: "intro",
  difficulty: 1,
  playerSecret: "",
  computerSecret: "",
  turn: "player",
  logs: [],
  winner: null,
  roundOutcome: {
    playerSolved: false,
    computerSolved: false
  },
  waitingComputer: false,
  showComputerLogs: true,
  computerMemoDigits: ["", "", "", ""],
  editingMemoIndex: null,
  computerAi: createComputerAiState()
};

function createComputerAiState() {
  return {
    candidateIndices: [],
    lastGuessIndex: null
  };
}

function createSlots(container, values, hidden, editable) {
  container.innerHTML = "";

  values.forEach((value, index) => {
    const slot = document.createElement(editable ? "button" : "div");
    const classNames = [`slot`, hidden ? "hidden" : "revealed"];

    if (editable) {
      slot.type = "button";
      slot.dataset.index = String(index);
      slot.setAttribute("aria-label", `컴퓨터 숫자 메모 ${index + 1}번 칸`);
    }

    if (hidden && value !== "?") {
      classNames.push("memo-filled");
    }

    if (editable && state.editingMemoIndex === index) {
      classNames.push("memo-editing");
    }

    slot.className = classNames.join(" ");

    if (editable && state.editingMemoIndex === index) {
      const input = document.createElement("input");
      input.className = "slot-input";
      input.type = "text";
      input.inputMode = "numeric";
      input.maxLength = 1;
      input.value = state.computerMemoDigits[index];
      input.dataset.index = String(index);
      slot.appendChild(input);
    } else {
      slot.textContent = value;
    }

    container.appendChild(slot);
  });
}

function render() {
  introScreen.hidden = state.screen !== "intro";
  gameScreen.hidden = state.screen !== "game";

  if (state.screen !== "game") {
    return;
  }

  createSlots(computerSecretSlots, computerSlotValues(), true, true);
  createSlots(playerSecretSlots, state.playerSecret.split(""), false, false);

  difficultyText.textContent = `난이도: ${state.difficulty}`;
  resultText.textContent = state.winner ? winnerLabel(state.winner) : "진행 중";
  turnText.textContent = turnLabel();
  statusText.textContent = statusLabel();
  thinkingNotice.hidden = !state.waitingComputer;
  computerLogBox.parentElement.hidden = !state.showComputerLogs;

  eventLogBox.innerHTML = "";
  playerLogBox.innerHTML = "";
  computerLogBox.innerHTML = "";

  state.logs.forEach((entry) => {
    if (entry.type === "guess") {
      const row = buildGuessLogRow(entry);
      const targetBox = entry.title === "컴퓨터" ? computerLogBox : playerLogBox;

      if (entry.title === "컴퓨터" && !state.showComputerLogs) {
        return;
      }

      targetBox.appendChild(row);
      return;
    }

    eventLogBox.appendChild(buildTextLogRow(entry));
  });

  eventLogBox.scrollTop = eventLogBox.scrollHeight;
  playerLogBox.scrollTop = playerLogBox.scrollHeight;
  computerLogBox.scrollTop = computerLogBox.scrollHeight;

  const playerTurn = state.turn === "player" && !state.winner;
  guessInput.disabled = !playerTurn;
  guessButton.disabled = !playerTurn;
  restartButton.hidden = !state.winner;

  if (state.editingMemoIndex !== null) {
    const activeInput = computerSecretSlots.querySelector(".slot-input");
    if (activeInput) {
      activeInput.focus();
      activeInput.select();
      return;
    }
  }

  if (playerTurn) {
    guessInput.focus();
  }
}

function buildGuessLogRow(entry) {
  const row = document.createElement("div");
  row.className = "log-grid";
  row.innerHTML = [
    `<div class="log-cell log-cell-main"><strong>${entry.title}</strong><span>${entry.guess}</span></div>`,
    `<div class="log-cell log-cell-strike"><strong>S</strong><span>${entry.strike}</span></div>`,
    `<div class="log-cell log-cell-ball"><strong>B</strong><span>${entry.ball}</span></div>`
  ].join("");
  return row;
}

function buildTextLogRow(entry) {
  const row = document.createElement("div");
  row.className = "log-row";
  row.innerHTML = `<strong>${entry.title}</strong><br>${entry.text}`;
  return row;
}

function generateAllCandidates() {
  if (allCandidatesCache) {
    return allCandidatesCache;
  }

  const result = [];
  const used = Array(10).fill(false);

  function dfs(path) {
    if (path.length === 4) {
      result.push(path.join(""));
      return;
    }

    for (let digit = 0; digit < 10; digit += 1) {
      if (used[digit]) {
        continue;
      }

      used[digit] = true;
      path.push(String(digit));
      dfs(path);
      path.pop();
      used[digit] = false;
    }
  }

  dfs([]);
  allCandidatesCache = result;
  return result;
}

function scoreGuessEncoded(answer, guess) {
  const result = scoreGuess(guess, answer);
  return result.strike * 10 + result.ball;
}

function buildFeedbackTable(candidates) {
  if (feedbackTableCache) {
    return feedbackTableCache;
  }

  const size = candidates.length;
  const table = Array.from({ length: size }, () => new Uint8Array(size));

  for (let i = 0; i < size; i += 1) {
    for (let j = 0; j < size; j += 1) {
      table[i][j] = scoreGuessEncoded(candidates[i], candidates[j]);
    }
  }

  feedbackTableCache = table;
  return table;
}

function sampleIndices(indices, sampleSize) {
  const shuffled = indices.slice();

  for (let i = shuffled.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));
    const temp = shuffled[i];
    shuffled[i] = shuffled[j];
    shuffled[j] = temp;
  }

  return shuffled.slice(0, Math.min(sampleSize, shuffled.length));
}

function initializeComputerAi() {
  const allCandidates = generateAllCandidates();
  state.computerAi = {
    candidateIndices: allCandidates.map((_, index) => index),
    lastGuessIndex: null
  };
}

function filterCandidateIndices(candidateIndices, guessIndex, feedback) {
  const allCandidates = generateAllCandidates();

  if (state.difficulty === 3) {
    const table = buildFeedbackTable(allCandidates);
    return candidateIndices.filter((candidateIndex) => table[candidateIndex][guessIndex] === feedback);
  }

  const guess = allCandidates[guessIndex];
  return candidateIndices.filter((candidateIndex) => {
    const candidate = allCandidates[candidateIndex];
    return scoreGuessEncoded(candidate, guess) === feedback;
  });
}

function pickRandomIndex(indices) {
  return indices[Math.floor(Math.random() * indices.length)];
}

function pickKnuthGuess(candidateIndices) {
  const allCandidates = generateAllCandidates();
  const table = buildFeedbackTable(allCandidates);
  const guessPool = sampleIndices(candidateIndices, LEVEL3_SAMPLE_SIZE);

  let bestGuess = guessPool[0];
  let bestScore = Infinity;

  guessPool.forEach((guessIndex) => {
    const counts = new Uint16Array(50);
    let worst = 0;

    for (const targetIndex of candidateIndices) {
      const feedback = table[guessIndex][targetIndex];
      counts[feedback] += 1;

      if (counts[feedback] > worst) {
        worst = counts[feedback];
        if (worst >= bestScore) {
          break;
        }
      }
    }

    if (worst < bestScore) {
      bestScore = worst;
      bestGuess = guessIndex;
    }
  });

  return bestGuess;
}

function chooseComputerGuessIndex() {
  const allCandidates = generateAllCandidates();
  const { candidateIndices, lastGuessIndex } = state.computerAi;

  if (state.difficulty === 1) {
    return allCandidates.indexOf(randomDigits());
  }

  if (candidateIndices.length === 0) {
    initializeComputerAi();
  }

  if (state.difficulty === 2) {
    return pickRandomIndex(state.computerAi.candidateIndices);
  }

  if (lastGuessIndex === null) {
    return state.computerAi.candidateIndices[0];
  }

  return pickKnuthGuess(state.computerAi.candidateIndices);
}

function applyComputerFeedback(guessIndex, result) {
  if (state.difficulty === 1) {
    return;
  }

  const feedback = result.strike * 10 + result.ball;
  state.computerAi.candidateIndices = filterCandidateIndices(state.computerAi.candidateIndices, guessIndex, feedback);
  state.computerAi.lastGuessIndex = guessIndex;
}

function computerSlotValues() {
  return state.computerMemoDigits.map((digit) => digit || "?");
}

function winnerLabel(winner) {
  if (winner === "player") {
    return "결과: 내 승리";
  }

  if (winner === "computer") {
    return "결과: 컴퓨터 승리";
  }

  return "결과: 무승부";
}

function turnLabel() {
  if (state.winner) {
    return "라운드 종료";
  }

  if (state.turn === "player") {
    return "내 차례";
  }

  return "컴퓨터 차례";
}

function statusLabel() {
  if (state.winner) {
    return winnerLabel(state.winner);
  }

  if (state.turn === "player") {
    return "내 차례: 숫자 4개 입력";
  }

  if (state.roundOutcome.playerSolved) {
    return "컴퓨터 마지막 차례 진행 중";
  }

  return "컴퓨터가 숫자를 고르는 중";
}

function addLog(title, text) {
  state.logs.push({
    type: "text",
    title,
    text
  });
  render();
}

function addGuessLog(title, guess, result) {
  state.logs.push({
    type: "guess",
    title,
    guess,
    strike: result.strike,
    ball: result.ball
  });
  render();
}

function normalizeDigits(value) {
  return value.replace(/\D/g, "").slice(0, 4);
}

function normalizeMemoDigit(value) {
  return value.replace(/\D/g, "").slice(0, 1);
}

function isValidGuess(value) {
  if (value.length !== 4) {
    return false;
  }

  return new Set(value.split("")).size === 4;
}

function randomDigits() {
  const pool = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"];
  const digits = [];

  while (digits.length < 4) {
    const index = Math.floor(Math.random() * pool.length);
    digits.push(pool.splice(index, 1)[0]);
  }

  return digits.join("");
}

function scoreGuess(guess, answer) {
  let strike = 0;
  let ball = 0;

  guess.split("").forEach((digit, index) => {
    if (answer[index] === digit) {
      strike += 1;
      return;
    }

    if (answer.includes(digit)) {
      ball += 1;
    }
  });

  return { strike, ball };
}

function beginGame(difficulty, secret) {
  state.screen = "game";
  state.difficulty = difficulty;
  state.playerSecret = secret;
  state.computerSecret = randomDigits();
  state.turn = "player";
  state.logs = [];
  state.winner = null;
  state.roundOutcome.playerSolved = false;
  state.roundOutcome.computerSolved = false;
  state.waitingComputer = false;
  state.showComputerLogs = true;
  state.computerMemoDigits = ["", "", "", ""];
  state.editingMemoIndex = null;
  initializeComputerAi();

  guessInput.value = "";
  guessMessage.textContent = "";
  computerLogToggle.checked = true;
  addLog("시작", `난이도 ${difficulty}, 내 숫자 ${secret}`);
  render();
}

function finalizeRoundIfNeeded() {
  if (!state.roundOutcome.playerSolved && !state.roundOutcome.computerSolved) {
    state.turn = "player";
    render();
    return;
  }

  if (state.roundOutcome.playerSolved && state.roundOutcome.computerSolved) {
    state.winner = "draw";
    addLog("종료", "이번 라운드는 무승부");
    return;
  }

  if (state.roundOutcome.playerSolved) {
    state.winner = "player";
    addLog("종료", "내가 먼저 맞혔다");
    return;
  }

  state.winner = "computer";
  addLog("종료", "컴퓨터가 맞혔다");
}

function runComputerTurn() {
  state.turn = "computer";
  state.waitingComputer = true;
  render();

  const delay = COMPUTER_DELAYS[state.difficulty];

  window.setTimeout(() => {
    const guessIndex = chooseComputerGuessIndex();
    const guess = generateAllCandidates()[guessIndex];
    const result = scoreGuess(guess, state.playerSecret);

    state.waitingComputer = false;
    addGuessLog("컴퓨터", guess, result);
    applyComputerFeedback(guessIndex, result);

    if (result.strike === 4) {
      state.roundOutcome.computerSolved = true;
    }

    finalizeRoundIfNeeded();
  }, delay);
}

setupForm.addEventListener("submit", (event) => {
  event.preventDefault();

  const formData = new FormData(setupForm);
  const difficulty = Number(formData.get("difficulty"));
  const secret = normalizeDigits(playerSecretInput.value);

  playerSecretInput.value = secret;

  if (!isValidGuess(secret)) {
    setupMessage.textContent = "중복 없는 숫자 4개를 입력해야 한다.";
    return;
  }

  setupMessage.textContent = "";
  beginGame(difficulty, secret);
});

guessForm.addEventListener("submit", (event) => {
  event.preventDefault();

  if (state.turn !== "player" || state.winner) {
    return;
  }

  const guess = normalizeDigits(guessInput.value);
  guessInput.value = guess;

  if (!isValidGuess(guess)) {
    guessMessage.textContent = "중복 없는 숫자 4개를 입력해야 한다.";
    return;
  }

  guessMessage.textContent = "";

  const result = scoreGuess(guess, state.computerSecret);
  addGuessLog("나", guess, result);

  if (result.strike === 4) {
    state.roundOutcome.playerSolved = true;
    addLog("상태", "내가 맞혔다. 컴퓨터 마지막 차례를 진행한다.");
  }

  guessInput.value = "";
  runComputerTurn();
});

restartButton.addEventListener("click", () => {
  state.screen = "intro";
  state.playerSecret = "";
  state.computerSecret = "";
  state.turn = "player";
  state.logs = [];
  state.winner = null;
  state.roundOutcome.playerSolved = false;
  state.roundOutcome.computerSolved = false;
  state.waitingComputer = false;
  state.showComputerLogs = true;
  state.computerMemoDigits = ["", "", "", ""];
  state.editingMemoIndex = null;
  state.computerAi = createComputerAiState();
  playerSecretInput.value = "";
  guessInput.value = "";
  guessMessage.textContent = "";
  setupMessage.textContent = "";
  computerLogToggle.checked = true;
  render();
});

computerLogToggle.addEventListener("change", () => {
  state.showComputerLogs = computerLogToggle.checked;
  render();
});

computerSecretSlots.addEventListener("click", (event) => {
  const slotButton = event.target.closest(".slot.hidden");
  if (!slotButton) {
    return;
  }

  state.editingMemoIndex = Number(slotButton.dataset.index);
  render();
});

computerSecretSlots.addEventListener("input", (event) => {
  const input = event.target.closest(".slot-input");
  if (!input) {
    return;
  }

  const index = Number(input.dataset.index);
  const value = normalizeMemoDigit(input.value);
  input.value = value;
  state.computerMemoDigits[index] = value;
});

computerSecretSlots.addEventListener("keydown", (event) => {
  const input = event.target.closest(".slot-input");
  if (!input) {
    return;
  }

  if (event.key === "Enter" || event.key === "Escape") {
    event.preventDefault();
    input.blur();
  }
});

computerSecretSlots.addEventListener("focusout", (event) => {
  const input = event.target.closest(".slot-input");
  if (!input) {
    return;
  }

  const index = Number(input.dataset.index);
  state.computerMemoDigits[index] = normalizeMemoDigit(input.value);
  state.editingMemoIndex = null;
  render();
});

playerSecretInput.addEventListener("input", () => {
  playerSecretInput.value = normalizeDigits(playerSecretInput.value);
});

guessInput.addEventListener("input", () => {
  guessInput.value = normalizeDigits(guessInput.value);
});

render();
