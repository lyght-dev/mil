const elements = {
  lastFetch: query("#lf"),
  fetchStatus: query("#fs"),
  endpoint: query("#ep"),
  refreshIntervalMinutes: query("#ri"),
  refreshButton: query("#rf"),
  autoRefreshToggle: query("#ar"),
  heatmapBody: query("#hm-body")
};

const endpoint = new URL("/pings", window.location.href).href;
const autoRefreshIntervalMs = 60000;

let refreshTimer = null;
let lastSuccessAt = null;

function query(selector) {
  return document.querySelector(selector);
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function formatRtt(value) {
  if (value == null) {
    return "—";
  }

  return `${escapeHtml(String(value))} ms`;
}

function isSuccessStatus(status) {
  return status === "success";
}

function toStatusLabel(status) {
  if (status === "success") {
    return "정상";
  }

  if (status === "timeout") {
    return "시간 초과";
  }

  if (status === "error") {
    return "오류";
  }

  return status || "오류";
}

function renderHeatmap(records) {
  if (!Array.isArray(records) || records.length === 0) {
    elements.heatmapBody.innerHTML = '<div class="empty">데이터가 없습니다.</div>';
    return;
  }

  const cells = records
    .slice()
    .sort((a, b) => (a?.destination || "").localeCompare(b?.destination || ""))
    .map((record) => {
      const destination = record?.destination || "—";
      const status = record?.status || "error";
      const statusLabel = toStatusLabel(status);
      const cellClass = isSuccessStatus(status) ? "ok" : "bad";

      return `<article class="cell ${cellClass}" title="${escapeHtml(destination)}: ${escapeHtml(statusLabel)}">
        <div class="host">${escapeHtml(destination)}</div>
        <div class="status">${escapeHtml(statusLabel)}</div>
        <div class="rtt">${formatRtt(record?.rtt)}</div>
      </article>`;
    })
    .join("");

  elements.heatmapBody.innerHTML = cells;
}

function setFetchStatus(text, className) {
  elements.fetchStatus.textContent = text;
  elements.fetchStatus.className = className || "";
}

async function fetchAndRender() {
  try {
    setFetchStatus("조회 중...");
    const response = await fetch(endpoint, { method: "GET" });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    renderHeatmap(await response.json());

    lastSuccessAt = new Date();
    elements.lastFetch.textContent = lastSuccessAt.toLocaleString("ko-KR");
    setFetchStatus("정상", "ok");
  } catch (error) {
    const message = error?.message || String(error);
    setFetchStatus(`오류: ${message}`, "bad");
    elements.lastFetch.textContent = lastSuccessAt ? lastSuccessAt.toLocaleString("ko-KR") : "—";
  }
}

function startAutoRefresh() {
  stopAutoRefresh();
  refreshTimer = setInterval(() => {
    void fetchAndRender();
  }, autoRefreshIntervalMs);
}

function stopAutoRefresh() {
  if (refreshTimer == null) {
    return;
  }

  clearInterval(refreshTimer);
  refreshTimer = null;
}

function initialize() {
  elements.endpoint.textContent = endpoint;
  elements.refreshIntervalMinutes.textContent = String(autoRefreshIntervalMs / 60000);
  elements.refreshButton.addEventListener("click", () => void fetchAndRender());
  elements.autoRefreshToggle.addEventListener("change", () => {
    if (elements.autoRefreshToggle.checked) {
      startAutoRefresh();
      return;
    }

    stopAutoRefresh();
  });

  void fetchAndRender();
  startAutoRefresh();
}

initialize();
