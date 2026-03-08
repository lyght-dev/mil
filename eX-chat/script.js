(function () {
  const stateEl = document.getElementById("conn-state");
  const messagesEl = document.getElementById("messages");
  const formEl = document.getElementById("chat-form");
  const inputEl = document.getElementById("chat-input");

  let socket = null;

  function endpoint() {
    const proto = location.protocol === "https:" ? "wss:" : "ws:";
    return proto + "//" + location.host + "/ws";
  }

  function setState(kind, text) {
    stateEl.textContent = text;
    stateEl.className = "badge";
    if (kind === "open") {
      stateEl.classList.add("badge-ok");
      return;
    }
    if (kind === "closed") {
      stateEl.classList.add("badge-off");
      return;
    }
    stateEl.classList.add("badge-warn");
  }

  function nowLabel() {
    return new Date().toLocaleTimeString([], {
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit"
    });
  }

  function addMessage(payload) {
    const row = document.createElement("article");
    row.className = payload.type === "system" ? "msg msg-system" : "msg";

    const meta = document.createElement("div");
    meta.className = "meta";

    if (payload.type === "chat") {
      const who = document.createElement("span");
      who.className = "sender";
      who.textContent = payload.sender || "unknown";
      meta.appendChild(who);
    } else {
      const sys = document.createElement("span");
      sys.className = "sender sender-system";
      sys.textContent = "system";
      meta.appendChild(sys);
    }

    const time = document.createElement("time");
    time.className = "time";
    time.textContent = nowLabel();
    meta.appendChild(time);

    const text = document.createElement("div");
    text.className = "text";
    text.textContent = payload.text || "";

    row.appendChild(meta);
    row.appendChild(text);
    messagesEl.appendChild(row);
    messagesEl.scrollTop = messagesEl.scrollHeight;
  }

  function connect() {
    setState("connecting", "connecting");
    socket = new WebSocket(endpoint());

    socket.addEventListener("open", function () {
      setState("open", "connected");
    });

    socket.addEventListener("message", function (event) {
      const payload = JSON.parse(event.data);
      addMessage(payload);
    });

    socket.addEventListener("close", function () {
      setState("closed", "disconnected");
    });

    socket.addEventListener("error", function () {
      setState("closed", "error");
    });
  }

  formEl.addEventListener("submit", function (event) {
    event.preventDefault();

    const text = inputEl.value.trim();
    if (!text) {
      inputEl.focus();
      return;
    }

    if (!socket || socket.readyState !== WebSocket.OPEN) {
      addMessage({ type: "system", text: "not connected" });
      return;
    }

    socket.send(text);
    inputEl.value = "";
    inputEl.focus();
  });

  connect();
})();
