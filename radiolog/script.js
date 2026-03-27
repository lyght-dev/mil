const STORAGE_DATE_KEY = "radiolog:selectedDate";
const STORAGE_JOURNAL_PREFIX = "radiolog:journal:";
const STORAGE_AUTHOR_PREFIX = "radiolog:author:";
const SIGNAL_OPTIONS = ["", "1/1", "2/2", "3/3"];
const RANK_OPTIONS = ["", "이병", "일병", "상병", "병장"];

const DIVISION_NETWORKS = ["작전망", "행정군수망"];
const DIVISION_SLOTS = ["오전", "오후"];
const BRIGADE_UNITS = ["0FA", "1FA", "2FA", "3FA", "4FA"];
const BRIGADE_CF_SLOTS = [
  { slotKey: "08:00", label: "08:00", isManualTime: false },
  { slotKey: "10:00", label: "10:00", isManualTime: false },
  { slotKey: "12:00", label: "12:00", isManualTime: false },
  { slotKey: "14:00", label: "14:00", isManualTime: false },
  { slotKey: "16:00", label: "16:00", isManualTime: false },
  { slotKey: "CF-직접입력-1", label: "직접입력 1", isManualTime: true },
  { slotKey: "CF-직접입력-2", label: "직접입력 2", isManualTime: true }
];
const BRIGADE_F_SLOTS = [{ slotKey: "12:00", label: "직접입력", isManualTime: true }];
const CF_MANUAL_SLOT_KEYS = BRIGADE_CF_SLOTS.filter((slot) => slot.isManualTime).map(
  (slot) => slot.slotKey
);

const elements = {
  dateInput: document.querySelector("#date-input"),
  todayButton: document.querySelector("#today-btn"),
  resetButton: document.querySelector("#reset-btn"),
  authorAm: document.querySelector("#author-am"),
  authorPm: document.querySelector("#author-pm"),
  journalBlocks: document.querySelector("#journal-blocks"),
  divisionBody: document.querySelector("#division-body"),
  brigadeCfBody: document.querySelector("#brigade-cf-body"),
  brigadeFBody: document.querySelector("#brigade-f-body")
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

function getAuthorStorageKey(dateString) {
  return `${STORAGE_AUTHOR_PREFIX}${dateString}`;
}

function buildTemplateRows(dateString) {
  const rows = [];
  let sequence = 1;

  DIVISION_NETWORKS.forEach((network) => {
    DIVISION_SLOTS.forEach((slotLabel) => {
      rows.push(createTemplateRow(dateString, sequence, "사단망", network, slotLabel, "1DIV"));
      sequence += 1;
    });
  });

  BRIGADE_CF_SLOTS.forEach((slot) => {
    BRIGADE_UNITS.forEach((unit) => {
      rows.push(createTemplateRow(dateString, sequence, "여단망", "CF", slot.slotKey, unit));
      sequence += 1;
    });
  });

  BRIGADE_F_SLOTS.forEach((slot) => {
    BRIGADE_UNITS.forEach((unit) => {
      rows.push(createTemplateRow(dateString, sequence, "여단망", "F", slot.slotKey, unit));
      sequence += 1;
    });
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
    recordedTime: "",
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
      recordedTime: typeof stored.recordedTime === "string" ? stored.recordedTime : "",
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
}

function readStoredAuthors(dateString) {
  const raw = localStorage.getItem(getAuthorStorageKey(dateString));
  if (!raw) {
    return { am: "", pm: "" };
  }

  try {
    const parsed = JSON.parse(raw);
    return {
      am: typeof parsed?.am === "string" ? parsed.am : "",
      pm: typeof parsed?.pm === "string" ? parsed.pm : ""
    };
  } catch (error) {
    return { am: "", pm: "" };
  }
}

function loadAuthorFields(dateString) {
  const author = readStoredAuthors(dateString);
  elements.authorAm.value = author.am;
  elements.authorPm.value = author.pm;
}

function saveAuthorFields() {
  const payload = {
    am: elements.authorAm.value || "",
    pm: elements.authorPm.value || ""
  };
  localStorage.setItem(getAuthorStorageKey(state.currentDate), JSON.stringify(payload));
}

function isDivisionRow(row) {
  return row.linkType === "사단망";
}

function isCfManualRow(row) {
  return (
    row.linkType === "여단망" &&
    row.network === "CF" &&
    CF_MANUAL_SLOT_KEYS.includes(row.slotLabel)
  );
}

function isFRow(row) {
  return row.linkType === "여단망" && row.network === "F";
}

function requiresRecordedTime(row) {
  return isDivisionRow(row) || isCfManualRow(row) || isFRow(row);
}

function isRowComplete(row) {
  const hasBaseFields = Boolean(
    row.txSignal &&
      row.rxSignal &&
      row.counterpartyRank &&
      row.counterpartyName &&
      row.counterpartyName.trim()
  );

  if (!hasBaseFields) {
    return false;
  }

  if (!requiresRecordedTime(row)) {
    return true;
  }

  return Boolean(row.recordedTime);
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

function getRowKey(linkType, network, slotLabel, targetUnit) {
  return `${linkType}|${network}|${slotLabel}|${targetUnit}`;
}

function createRowLookup(rows) {
  const lookup = new Map();
  rows.forEach((row) => {
    lookup.set(getRowKey(row.linkType, row.network, row.slotLabel, row.targetUnit), row);
  });
  return lookup;
}

function findRow(lookup, linkType, network, slotLabel, targetUnit) {
  return lookup.get(getRowKey(linkType, network, slotLabel, targetUnit)) || null;
}

function renderEditorCell(row) {
  if (!row) {
    return '<td class="matrix-cell"><div class="cell-editor missing">-</div></td>';
  }

  const complete = isRowComplete(row);
  const stateClass = complete ? "complete" : "pending";
  const divisionTimeField = isDivisionRow(row)
    ? `<label class="editor-field time-field">
          <span>실제시간</span>
          <input data-id="${escapeHtml(row.id)}" data-field="recordedTime" type="time" value="${escapeHtml(row.recordedTime)}" />
        </label>`
    : "";

  return `<td class="matrix-cell">
    <div class="cell-editor ${stateClass}" data-row-cell="${escapeHtml(row.id)}">
      <div class="editor-grid">
        <label class="editor-field">
          <span>송신</span>
          <select data-id="${escapeHtml(row.id)}" data-field="txSignal">
            ${renderSelectOptions(SIGNAL_OPTIONS, row.txSignal)}
          </select>
        </label>
        <label class="editor-field">
          <span>수신</span>
          <select data-id="${escapeHtml(row.id)}" data-field="rxSignal">
            ${renderSelectOptions(SIGNAL_OPTIONS, row.rxSignal)}
          </select>
        </label>
        <label class="editor-field">
          <span>관등</span>
          <select data-id="${escapeHtml(row.id)}" data-field="counterpartyRank">
            ${renderSelectOptions(RANK_OPTIONS, row.counterpartyRank)}
          </select>
        </label>
        <label class="editor-field">
          <span>성명</span>
          <input data-id="${escapeHtml(row.id)}" data-field="counterpartyName" type="text" value="${escapeHtml(row.counterpartyName)}" />
        </label>
        ${divisionTimeField}
      </div>
    </div>
  </td>`;
}

function renderDivisionRows(lookup) {
  elements.divisionBody.innerHTML = DIVISION_NETWORKS
    .map((network) => {
      const cells = DIVISION_SLOTS
        .map((slotLabel) => renderEditorCell(findRow(lookup, "사단망", network, slotLabel, "1DIV")))
        .join("");
      return `<tr>
        <th class="row-label" scope="row">${escapeHtml(network)}</th>
        ${cells}
      </tr>`;
    })
    .join("");
}

function getBrigadeSlotTimeValue(lookup, network, slotKey) {
  for (const unit of BRIGADE_UNITS) {
    const row = findRow(lookup, "여단망", network, slotKey, unit);
    if (row) {
      return row.recordedTime || "";
    }
  }
  return "";
}

function renderBrigadeSlotLabel(lookup, network, slot) {
  if (!slot.isManualTime) {
    return escapeHtml(slot.label);
  }

  const value = getBrigadeSlotTimeValue(lookup, network, slot.slotKey);
  return `<label class="slot-time-field">
    <span>${escapeHtml(slot.label)}</span>
    <input
      type="time"
      data-time-scope="brigade-slot"
      data-network="${escapeHtml(network)}"
      data-slot="${escapeHtml(slot.slotKey)}"
      value="${escapeHtml(value)}"
    />
  </label>`;
}

function renderBrigadeRows(lookup, network, slots, bodyElement) {
  bodyElement.innerHTML = slots
    .map((slot) => {
      const cells = BRIGADE_UNITS
        .map((unit) => renderEditorCell(findRow(lookup, "여단망", network, slot.slotKey, unit)))
        .join("");
      return `<tr>
        <th class="row-label" scope="row">${renderBrigadeSlotLabel(lookup, network, slot)}</th>
        ${cells}
      </tr>`;
    })
    .join("");
}

function renderTables() {
  const lookup = createRowLookup(state.rows);
  renderDivisionRows(lookup);
  renderBrigadeRows(lookup, "CF", BRIGADE_CF_SLOTS, elements.brigadeCfBody);
  renderBrigadeRows(lookup, "F", BRIGADE_F_SLOTS, elements.brigadeFBody);
}

function loadDate(dateString) {
  const storedRows = readStoredRows(dateString);
  const rows = normalizeRows(dateString, storedRows);

  state.currentDate = dateString;
  state.rows = rows;
  elements.dateInput.value = dateString;

  loadAuthorFields(dateString);
  renderTables();

  if (!storedRows) {
    saveCurrentRows();
    return;
  }

  localStorage.setItem(STORAGE_DATE_KEY, dateString);
}

function findCellElement(rowId) {
  const cells = document.querySelectorAll("[data-row-cell]");
  for (const cell of cells) {
    if (cell.dataset.rowCell === rowId) {
      return cell;
    }
  }
  return null;
}

function syncCellState(row) {
  const cell = findCellElement(row.id);
  if (!cell) {
    return;
  }

  const complete = isRowComplete(row);
  cell.classList.toggle("pending", !complete);
  cell.classList.toggle("complete", complete);
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

  saveCurrentRows();
  syncCellState(row);
}

function updateBrigadeSlotTime(target) {
  const network = target.dataset.network;
  const slot = target.dataset.slot;
  if (!network || !slot) {
    return;
  }

  const value = typeof target.value === "string" ? target.value : "";
  let touched = false;

  state.rows.forEach((row) => {
    if (row.linkType !== "여단망") {
      return;
    }
    if (row.network !== network || row.slotLabel !== slot) {
      return;
    }
    row.recordedTime = value;
    syncCellState(row);
    touched = true;
  });

  if (!touched) {
    return;
  }

  saveCurrentRows();
}

function handleAuthorInput(event) {
  if (!(event.target instanceof HTMLInputElement)) {
    return;
  }

  if (event.target !== elements.authorAm && event.target !== elements.authorPm) {
    return;
  }

  saveAuthorFields();
}

function handleRowsInput(event) {
  const target = event.target;
  if (!(target instanceof HTMLInputElement) && !(target instanceof HTMLSelectElement)) {
    return;
  }

  if (target instanceof HTMLInputElement && target.dataset.timeScope === "brigade-slot") {
    updateBrigadeSlotTime(target);
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
  renderTables();
}

function initialize() {
  elements.journalBlocks.addEventListener("input", handleRowsInput);
  elements.journalBlocks.addEventListener("change", handleRowsInput);
  elements.authorAm.addEventListener("input", handleAuthorInput);
  elements.authorPm.addEventListener("input", handleAuthorInput);
  elements.dateInput.addEventListener("change", handleDateChange);
  elements.todayButton.addEventListener("click", handleTodayClick);
  elements.resetButton.addEventListener("click", handleResetClick);

  const savedDate = localStorage.getItem(STORAGE_DATE_KEY);
  const initialDate = savedDate || getToday();
  loadDate(initialDate);
}

initialize();
