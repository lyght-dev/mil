const elements = {
  rows: query("#rows"),
  lastFetch: query("#lf"),
  fetchStatus: query("#fs"),
  endpoint: query("#ep"),
  refreshButton: query("#rf"),
  autoRefreshToggle: query("#ar")
};

const endpoint = new URL("/pings", window.location.href).href;

let refreshTimer = null;
let lastSuccessAt = null;

function query(selector) {
  return document.querySelector(selector);
}

function formatDateTime(value) {
  if (!value) {
    return "—";
  }

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : date.toLocaleString();
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function getBadgeClass(status) {
  if (status === "success") {
    return "s";
  }

  if (status === "timeout") {
    return "t";
  }

  return "x";
}

function renderBadge(status) {
  const safeStatus = status || "error";
  return `<span class="b ${getBadgeClass(safeStatus)}">${escapeHtml(safeStatus)}</span>`;
}

function renderRows(records) {
  const renderedAt = escapeHtml(new Date().toLocaleString());

  if (!Array.isArray(records) || records.length === 0) {
    elements.rows.innerHTML = `<tr><td colspan="5" class="e">No data.</td></tr>`;
    return;
  }

  elements.rows.innerHTML = records
    .map((record) => renderRow(record, renderedAt))
    .join("");
}

function renderRow(record, renderedAt) {
  const destination = record?.dest ?? "—";
  const rtt = record?.rtt == null ? "—" : escapeHtml(String(record.rtt));

  return `
    <tr>
      <td class="mono">${escapeHtml(destination)}</td>
      <td>${renderBadge(record?.status)}</td>
      <td class="num">${rtt}</td>
      <td>${escapeHtml(formatDateTime(record?.successedAt))}</td>
      <td>${renderedAt}</td>
    </tr>`;
}

function setFetchStatus(text, className) {
  elements.fetchStatus.textContent = text;
  elements.fetchStatus.className = className || "";
}

async function fetchAndRender() {
  try {
    setFetchStatus("Fetching...");
    const response = await fetch(endpoint, { method: "GET" });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    renderRows(await response.json());
    lastSuccessAt = new Date();
    elements.lastFetch.textContent = lastSuccessAt.toLocaleString();
    setFetchStatus("OK", "ok");
  } catch (error) {
    const message = error?.message || String(error);
    setFetchStatus(`Error: ${message}`, "bad");
    elements.lastFetch.textContent = lastSuccessAt ? lastSuccessAt.toLocaleString() : "—";
  }
}

function startAutoRefresh() {
  stopAutoRefresh();
  refreshTimer = setInterval(() => {
    void fetchAndRender();
  }, 10000);
}

function stopAutoRefresh() {
  if (refreshTimer == null) {
    return;
  }

  clearInterval(refreshTimer);
  refreshTimer = null;
}

function handleRefreshClick() {
  void fetchAndRender();
}

function handleAutoRefreshChange() {
  if (elements.autoRefreshToggle.checked) {
    startAutoRefresh();
    return;
  }

  stopAutoRefresh();
}

function initialize() {
  elements.endpoint.textContent = endpoint;
  elements.refreshButton.addEventListener("click", handleRefreshClick);
  elements.autoRefreshToggle.addEventListener("change", handleAutoRefreshChange);

  void fetchAndRender();
  startAutoRefresh();
}

initialize();
