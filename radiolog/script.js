const STORAGE_DATE_KEY = "radiolog:selectedDate";
const STORAGE_JOURNAL_PREFIX = "radiolog:journal:";
const SIGNAL_OPTIONS = ["", "1/1", "2/2", "3/3"];
const RANK_OPTIONS = ["", "이병", "일병", "상병", "병장"];
const BRIGADE_UNITS = ["0FA", "1FA", "2FA", "3FA", "4FA"];

const elements = {
  dateInput: document.querySelector("#date-input"),
  todayButton: document.querySelector("#today-btn"),
  resetButton: document.querySelector("#reset-btn"),
  totalCount: document.querySelector("#total-count"),
  doneCount: document.querySelector("#done-count"),
  pendingCount: document.querySelector("#pending-count"),
  saveStatus: document.querySelector("#save-status"),
  rowsBody: document.querySelector("#rows")
};

const state = {
  currentDate: "",
  rows: []
};

function formatDate(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function getToday() {
  return formatDate(new Date());
}

function getStorageKey(dateString) {
  return `${STORAGE_JOURNAL_PREFIX}${dateString}`;
}

function buildTemplateRows(dateString) {
  const rows = [];
  let sequence = 1;

  ["작전망", "행정군수망"].forEach((network) => {
    ["오전", "오후"].forEach((slotLabel) => {
      rows.push(createTemplateRow(dateString, sequence, "사단망", network, slotLabel, "1DIV"));
      sequence += 1;
    });
  });

  ["08:00", "10:00", "12:00", "14:00", "16:00"].forEach((slotLabel) => {
    BRIGADE_UNITS.forEach((unit) => {
      rows.push(createTemplateRow(dateString, sequence, "여단망", "CF", slotLabel, unit));
      sequence += 1;
    });
  });

  BRIGADE_UNITS.forEach((unit) => {
    rows.push(createTemplateRow(dateString, sequence, "여단망", "F", "12:00", unit));
    sequence += 1;
  });

  return rows;
}

function createTemplateRow(dateString, sequence, linkType, network, slotLabel, targetUnit) {
  const keyPart = `${linkType}-${network}-${slotLabel}-${targetUnit}`
    .replaceAll(":", "-")
    .replaceAll("/", "-");

  return {
    id: `${dateString}-${keyPart}`,
    sequence,
    date: dateString,
    linkType,
    network,
    slotLabel,
    targetUnit,
    txSignal: "",
    rxSignal: "",
    counterpartyRank: "",
    counterpartyName: "",
    updatedAt: ""
  };
}

function readStoredRows(dateString) {
  const raw = localStorage.getItem(getStorageKey(dateString));
  if (!raw) {
    return null;
  }

  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) {
      return null;
    }
    return parsed;
  } catch (error) {
    return null;
  }
}

function normalizeRows(dateString, storedRows) {
  const template = buildTemplateRows(dateString);
  if (!storedRows) {
    return template;
  }

  const storedById = new Map(storedRows.map((row) => [row.id, row]));
  return template.map((row) => {
    const stored = storedById.get(row.id);
    if (!stored) {
      return row;
    }

    return {
      ...row,
      txSignal: normalizeOptionValue(stored.txSignal, SIGNAL_OPTIONS),
      rxSignal: normalizeOptionValue(stored.rxSignal, SIGNAL_OPTIONS),
      counterpartyRank: normalizeOptionValue(stored.counterpartyRank, RANK_OPTIONS),
      counterpartyName: typeof stored.counterpartyName === "string" ? stored.counterpartyName : "",
      updatedAt: typeof stored.updatedAt === "string" ? stored.updatedAt : ""
    };
  });
}

function normalizeOptionValue(value, options) {
  if (typeof value !== "string") {
    return "";
  }
  return options.includes(value) ? value : "";
}

function saveCurrentRows() {
  localStorage.setItem(getStorageKey(state.currentDate), JSON.stringify(state.rows));
  localStorage.setItem(STORAGE_DATE_KEY, state.currentDate);
  setSaveStatus(`자동 저장: ${new Date().toLocaleString("ko-KR", { hour12: false })}`);
}

function isRowComplete(row) {
  return Boolean(
    row.txSignal &&
      row.rxSignal &&
      row.counterpartyRank &&
      row.counterpartyName &&
      row.counterpartyName.trim()
  );
}

function updateSummary() {
  const total = state.rows.length;
  const done = state.rows.filter((row) => isRowComplete(row)).length;
  const pending = total - done;

  elements.totalCount.textContent = String(total);
  elements.doneCount.textContent = String(done);
  elements.pendingCount.textContent = String(pending);
}

function setSaveStatus(message) {
  elements.saveStatus.textContent = message;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function renderSelectOptions(options, selectedValue) {
  return options
    .map((value) => {
      const selected = value === selectedValue ? ' selected="selected"' : "";
      const label = value || "-";
      return `<option value="${escapeHtml(value)}"${selected}>${escapeHtml(label)}</option>`;
    })
    .join("");
}

function formatUpdatedAt(value) {
  if (!value) {
    return "-";
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "-";
  }
  return date.toLocaleString("ko-KR", { hour12: false });
}

function renderRows() {
  elements.rowsBody.innerHTML = state.rows
    .map((row) => {
      const rowClass = isRowComplete(row) ? "" : ' class="pending"';
      return `<tr data-id="${escapeHtml(row.id)}"${rowClass}>
        <td class="center">${row.sequence}</td>
        <td class="center">${escapeHtml(row.linkType)}</td>
        <td class="center">${escapeHtml(row.network)}</td>
        <td class="center">${escapeHtml(row.slotLabel)}</td>
        <td class="center">${escapeHtml(row.targetUnit)}</td>
        <td>
          <select data-id="${escapeHtml(row.id)}" data-field="txSignal">
            ${renderSelectOptions(SIGNAL_OPTIONS, row.txSignal)}
          </select>
        </td>
        <td>
          <select data-id="${escapeHtml(row.id)}" data-field="rxSignal">
            ${renderSelectOptions(SIGNAL_OPTIONS, row.rxSignal)}
          </select>
        </td>
        <td>
          <select data-id="${escapeHtml(row.id)}" data-field="counterpartyRank">
            ${renderSelectOptions(RANK_OPTIONS, row.counterpartyRank)}
          </select>
        </td>
        <td>
          <input data-id="${escapeHtml(row.id)}" data-field="counterpartyName" type="text" value="${escapeHtml(row.counterpartyName)}" />
        </td>
        <td class="time">${escapeHtml(formatUpdatedAt(row.updatedAt))}</td>
      </tr>`;
    })
    .join("");
}

function loadDate(dateString) {
  const storedRows = readStoredRows(dateString);
  const rows = normalizeRows(dateString, storedRows);

  state.currentDate = dateString;
  state.rows = rows;
  elements.dateInput.value = dateString;

  renderRows();
  updateSummary();

  if (!storedRows) {
    saveCurrentRows();
    return;
  }

  localStorage.setItem(STORAGE_DATE_KEY, dateString);
  setSaveStatus(`불러오기 완료: ${new Date().toLocaleString("ko-KR", { hour12: false })}`);
}

function updateRowField(target) {
  const id = target.dataset.id;
  const field = target.dataset.field;
  if (!id || !field) {
    return;
  }

  const row = state.rows.find((item) => item.id === id);
  if (!row) {
    return;
  }

  const value = typeof target.value === "string" ? target.value : "";
  row[field] = value;
  row.updatedAt = new Date().toISOString();

  saveCurrentRows();

  const tr = target.closest("tr");
  if (tr) {
    tr.classList.toggle("pending", !isRowComplete(row));
    const updatedAtCell = tr.querySelector(".time");
    if (updatedAtCell) {
      updatedAtCell.textContent = formatUpdatedAt(row.updatedAt);
    }
  }

  updateSummary();
}

function handleRowsInput(event) {
  const target = event.target;
  if (!(target instanceof HTMLInputElement) && !(target instanceof HTMLSelectElement)) {
    return;
  }
  if (!target.dataset.id || !target.dataset.field) {
    return;
  }
  updateRowField(target);
}

function handleDateChange() {
  if (!elements.dateInput.value) {
    return;
  }
  loadDate(elements.dateInput.value);
}

function handleTodayClick() {
  loadDate(getToday());
}

function handleResetClick() {
  const ok = window.confirm("해당 날짜 일지를 기본 양식으로 다시 생성합니다.");
  if (!ok) {
    return;
  }

  state.rows = buildTemplateRows(state.currentDate);
  saveCurrentRows();
  renderRows();
  updateSummary();
}

function initialize() {
  elements.rowsBody.addEventListener("input", handleRowsInput);
  elements.rowsBody.addEventListener("change", handleRowsInput);
  elements.dateInput.addEventListener("change", handleDateChange);
  elements.todayButton.addEventListener("click", handleTodayClick);
  elements.resetButton.addEventListener("click", handleResetClick);

  const savedDate = localStorage.getItem(STORAGE_DATE_KEY);
  const initialDate = savedDate || getToday();
  loadDate(initialDate);
}

initialize();
