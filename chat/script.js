const messagesEl = document.getElementById("messages");
const formEl = document.getElementById("chat-form");
const inputEl = document.getElementById("chat-input");
const buttonEl = document.getElementById("send-button");

let lastId = 0;

function sleep(ms) {
  return new Promise(function (resolve) {
    window.setTimeout(resolve, ms);
  });
}

async function fetchJson(url, options) {
  const response = await fetch(url, options);
  if (!response.ok) {
    throw new Error("HTTP " + response.status);
  }
  return response.json();
}

function formatTime(iso) {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) {
    return "";
  }
  return date.toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit"
  });
}

function addMessage(message) {
  const row = document.createElement("article");
  row.className = "msg";

  const meta = document.createElement("div");
  meta.className = "meta";

  const sender = document.createElement("span");
  sender.className = "sender";
  sender.textContent = message.sender || "unknown";

  const time = document.createElement("time");
  time.className = "time";
  time.textContent = formatTime(message.createdAt);

  const text = document.createElement("div");
  text.className = "text";
  text.textContent = message.text || "";

  meta.appendChild(sender);
  meta.appendChild(time);
  row.appendChild(meta);
  row.appendChild(text);
  messagesEl.appendChild(row);
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

async function initCursor() {
  const payload = await fetchJson("/messages/latest");
  lastId = payload.latestId || 0;
}

async function pollLoop() {
  while (true) {
    try {
      const payload = await fetchJson("/messages?after=" + encodeURIComponent(lastId));
      const items = Array.isArray(payload) ? payload : (payload ? [payload] : []);

      if (items.length > 0) {
        items.forEach(addMessage);
        lastId = items[items.length - 1].id;
      }
    } catch (error) {
      console.error("poll failed", error);
      await sleep(2000);
    }
  }
}

async function handleSubmit(event) {
  event.preventDefault();

  const text = inputEl.value.trim();
  if (!text) {
    inputEl.focus();
    return;
  }

  buttonEl.disabled = true;

  try {
    await fetchJson("/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ text: text })
    });
    inputEl.value = "";
    inputEl.focus();
  } catch (error) {
    console.error("send failed", error);
    window.alert("메시지 전송에 실패했습니다.");
  } finally {
    buttonEl.disabled = false;
  }
}

async function start() {
  try {
    await initCursor();
    pollLoop();
  } catch (error) {
    console.error("startup failed", error);
    window.alert("채팅 초기화에 실패했습니다. 페이지를 새로고침해 주세요.");
  }
}

formEl.addEventListener("submit", handleSubmit);
start();
