const STORAGE_DATE_KEY = "radiolog:selectedDate";
const STORAGE_JOURNAL_PREFIX = "radiolog:journal:";
const STORAGE_AUTHOR_PREFIX = "radiolog:author:";
const SIGNAL_OPTIONS = ["", "1/1", "2/2", "3/3"];
const RANK_OPTIONS = ["", "이병", "일병", "상병", "병장"];
const PRE_RECEIVE_STATUS_OPTIONS = ["", "성공", "실패"];

const DIVISION_NETWORKS = ["작전망", "행정군수망"];
const DIVISION_SLOTS = ["오전", "오후"];
const PRE_SLOTS = ["08:00", "10:00", "12:00", "14:00", "16:00"];
const PRE_LINK_TYPE = "PRE";
const DIVISION_PRE_NETWORK = "PRE(행정군수망)";
const BRIGADE_PRE_NETWORK = "PRE(위치취합보고)";
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
  divisionPreBody: document.querySelector("#division-pre-body"),
  brigadeCfBody: document.querySelector("#brigade-cf-body"),
  brigadeFBody: document.querySelector("#brigade-f-body"),
  brigadePreBody: document.querySelector("#brigade-pre-body"),
  notePopover: document.querySelector("#note-popover"),
  noteTextarea: document.querySelector("#note-textarea"),
  noteCloseButton: document.querySelector("#note-close-btn")
};

const state = {
  currentDate: "",
  rows: [],
  activeNoteRowId: "",
  activeNoteAnchor: null
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

  PRE_SLOTS.forEach((slotLabel) => {
    rows.push(
      createTemplateRow(dateString, sequence, PRE_LINK_TYPE, DIVISION_PRE_NETWORK, slotLabel, "1DIV")
    );
    sequence += 1;
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

  PRE_SLOTS.forEach((slotLabel) => {
    BRIGADE_UNITS.forEach((unit) => {
      rows.push(
        createTemplateRow(dateString, sequence, PRE_LINK_TYPE, BRIGADE_PRE_NETWORK, slotLabel, unit)
      );
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
    preReceiveStatus: "",
    preReporter: "",
    note: "",
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

    const normalizedCounterpartyName =
      typeof stored.counterpartyName === "string" && stored.counterpartyName
        ? stored.counterpartyName
        : row.linkType === PRE_LINK_TYPE && typeof stored.preReporter === "string"
          ? stored.preReporter
          : "";

    return {
      ...row,
      txSignal: normalizeOptionValue(stored.txSignal, SIGNAL_OPTIONS),
      rxSignal: normalizeOptionValue(stored.rxSignal, SIGNAL_OPTIONS),
      counterpartyRank: normalizeOptionValue(stored.counterpartyRank, RANK_OPTIONS),
      counterpartyName: normalizedCounterpartyName,
      preReceiveStatus: normalizeOptionValue(stored.preReceiveStatus, PRE_RECEIVE_STATUS_OPTIONS),
      preReporter: typeof stored.preReporter === "string" ? stored.preReporter : "",
      note: typeof stored.note === "string" ? stored.note : "",
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

function isPreRow(row) {
  return row.linkType === PRE_LINK_TYPE;
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
  if (isPreRow(row)) {
    if (!row.preReceiveStatus) {
      return false;
    }

    if (row.preReceiveStatus === "성공") {
      return Boolean(row.counterpartyRank && row.counterpartyName && row.counterpartyName.trim());
    }

    return true;
  }

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

function renderGuideCell(labels) {
  const items = labels
    .map((label) => `<div class="guide-item">${escapeHtml(label)}</div>`)
    .join("");
  return `<td class="guide-label"><div class="guide-stack">${items}</div></td>`;
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

function renderNoteTrigger(row) {
  const hasNoteClass = row.note ? " has-note" : "";
  return `<button
      type="button"
      class="note-trigger${hasNoteClass}"
      aria-label="비고 입력"
      aria-expanded="false"
      data-note-trigger="${escapeHtml(row.id)}"
      data-note-tooltip="비고작성"
    >
      <span class="visually-hidden">비고</span>
    </button>`;
}

function renderPreCell(row) {
  if (!row) {
    return '<td class="matrix-cell"><div class="cell-editor missing">-</div></td>';
  }

  const complete = isRowComplete(row);
  const stateClass = complete ? "complete" : "pending";

  return `<td class="matrix-cell">
    <div class="cell-editor ${stateClass}" data-row-cell="${escapeHtml(row.id)}">
      ${renderNoteTrigger(row)}
      <div class="editor-grid">
        <div class="editor-row">
          <div class="editor-controls">
            <select
              class="editor-control"
              aria-label="수신 상태"
              data-id="${escapeHtml(row.id)}"
              data-field="preReceiveStatus"
            >
            ${renderSelectOptions(PRE_RECEIVE_STATUS_OPTIONS, row.preReceiveStatus)}
            </select>
          </div>
        </div>
        <div class="editor-row">
          <div class="editor-controls two-col">
            <select
              class="editor-control"
              aria-label="보고자 계급"
              data-id="${escapeHtml(row.id)}"
              data-field="counterpartyRank"
            >
              ${renderSelectOptions(RANK_OPTIONS, row.counterpartyRank)}
            </select>
            <input
              class="editor-control"
              aria-label="보고자 성명"
              data-id="${escapeHtml(row.id)}"
              data-field="counterpartyName"
              type="text"
              value="${escapeHtml(row.counterpartyName)}"
            />
          </div>
        </div>
      </div>
    </div>
  </td>`;
}

function renderEditorCell(row) {
  if (row && isPreRow(row)) {
    return renderPreCell(row);
  }

  if (!row) {
    return '<td class="matrix-cell"><div class="cell-editor missing">-</div></td>';
  }

  const complete = isRowComplete(row);
  const stateClass = complete ? "complete" : "pending";
  const divisionTimeField = isDivisionRow(row)
    ? `<div class="editor-row">
          <div class="editor-controls">
            <input
              class="editor-control"
              aria-label="교신시각"
              data-id="${escapeHtml(row.id)}"
              data-field="recordedTime"
              type="time"
              value="${escapeHtml(row.recordedTime)}"
            />
          </div>
        </div>`
    : "";

  return `<td class="matrix-cell">
    <div class="cell-editor ${stateClass}" data-row-cell="${escapeHtml(row.id)}">
      ${renderNoteTrigger(row)}
      <div class="editor-grid">
        ${divisionTimeField}
        <div class="editor-row">
          <div class="editor-controls two-col">
            <select
              class="editor-control"
              aria-label="송신 감명도"
              data-id="${escapeHtml(row.id)}"
              data-field="txSignal"
            >
              ${renderSelectOptions(SIGNAL_OPTIONS, row.txSignal)}
            </select>
            <select
              class="editor-control"
              aria-label="수신 감명도"
              data-id="${escapeHtml(row.id)}"
              data-field="rxSignal"
            >
              ${renderSelectOptions(SIGNAL_OPTIONS, row.rxSignal)}
            </select>
          </div>
        </div>
        <div class="editor-row">
          <div class="editor-controls two-col">
            <select
              class="editor-control"
              aria-label="상대 교신자 계급"
              data-id="${escapeHtml(row.id)}"
              data-field="counterpartyRank"
            >
              ${renderSelectOptions(RANK_OPTIONS, row.counterpartyRank)}
            </select>
            <input
              class="editor-control"
              aria-label="상대 교신자 성명"
              data-id="${escapeHtml(row.id)}"
              data-field="counterpartyName"
              type="text"
              value="${escapeHtml(row.counterpartyName)}"
            />
          </div>
        </div>
      </div>
    </div>
  </td>`;
}

function renderDivisionRows(lookup) {
  elements.divisionBody.innerHTML = DIVISION_SLOTS
    .map((slotLabel) => {
      const guideCell = renderGuideCell(["교신시각", "송수신 감명도", "교신자"]);
      const cells = DIVISION_NETWORKS
        .map((network) => renderEditorCell(findRow(lookup, "사단망", network, slotLabel, "1DIV")))
        .join("");
      return `<tr>
        <th class="row-label" scope="row">${escapeHtml(slotLabel)}</th>
        ${guideCell}
        ${cells}
      </tr>`;
    })
    .join("");
}

function renderDivisionPreRows(lookup) {
  elements.divisionPreBody.innerHTML = PRE_SLOTS
    .map((slotLabel) => {
      const row = findRow(lookup, PRE_LINK_TYPE, DIVISION_PRE_NETWORK, slotLabel, "1DIV");
      return `<tr>
        <th class="row-label" scope="row">${escapeHtml(slotLabel)}</th>
        ${renderGuideCell(["수신상태", "보고자"])}
        ${renderPreCell(row)}
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
  const guideCell = renderGuideCell(["송수신 감명도", "교신자"]);
  bodyElement.innerHTML = slots
    .map((slot) => {
      const cells = BRIGADE_UNITS
        .map((unit) => renderEditorCell(findRow(lookup, "여단망", network, slot.slotKey, unit)))
        .join("");
      return `<tr>
        <th class="row-label" scope="row">${renderBrigadeSlotLabel(lookup, network, slot)}</th>
        ${guideCell}
        ${cells}
      </tr>`;
    })
    .join("");
}

function renderBrigadePreRows(lookup) {
  const guideCell = renderGuideCell(["수신상태", "보고자"]);
  elements.brigadePreBody.innerHTML = PRE_SLOTS
    .map((slotLabel) => {
      const cells = BRIGADE_UNITS
        .map((unit) => renderPreCell(findRow(lookup, PRE_LINK_TYPE, BRIGADE_PRE_NETWORK, slotLabel, unit)))
        .join("");
      return `<tr>
        <th class="row-label" scope="row">${escapeHtml(slotLabel)}</th>
        ${guideCell}
        ${cells}
      </tr>`;
    })
    .join("");
}

function renderTables() {
  const lookup = createRowLookup(state.rows);
  renderDivisionRows(lookup);
  renderDivisionPreRows(lookup);
  renderBrigadeRows(lookup, "CF", BRIGADE_CF_SLOTS, elements.brigadeCfBody);
  renderBrigadeRows(lookup, "F", BRIGADE_F_SLOTS, elements.brigadeFBody);
  renderBrigadePreRows(lookup);
}

function getRowById(rowId) {
  return state.rows.find((row) => row.id === rowId) || null;
}

function findNoteTriggerButton(rowId) {
  const triggers = document.querySelectorAll("[data-note-trigger]");
  for (const trigger of triggers) {
    if (!(trigger instanceof HTMLButtonElement)) {
      continue;
    }
    if (trigger.dataset.noteTrigger === rowId) {
      return trigger;
    }
  }
  return null;
}

function updateNoteTriggerState(row) {
  const trigger = findNoteTriggerButton(row.id);
  if (!trigger) {
    return;
  }
  trigger.classList.toggle("has-note", Boolean(row.note));
}

function setActiveNoteTrigger(trigger) {
  trigger.classList.add("active");
  trigger.setAttribute("aria-expanded", "true");
}

function clearActiveNoteTrigger() {
  if (!(state.activeNoteAnchor instanceof HTMLButtonElement)) {
    return;
  }
  state.activeNoteAnchor.classList.remove("active");
  state.activeNoteAnchor.setAttribute("aria-expanded", "false");
}

function positionNotePopover() {
  if (!elements.notePopover || !(state.activeNoteAnchor instanceof HTMLButtonElement)) {
    return;
  }

  const margin = 8;
  const gap = 6;
  const anchorRect = state.activeNoteAnchor.getBoundingClientRect();
  const popover = elements.notePopover;
  const popoverRect = popover.getBoundingClientRect();

  let left = anchorRect.right - popoverRect.width;
  if (left < margin) {
    left = margin;
  }
  if (left + popoverRect.width > window.innerWidth - margin) {
    left = window.innerWidth - margin - popoverRect.width;
  }

  let top = anchorRect.bottom + gap;
  if (top + popoverRect.height > window.innerHeight - margin) {
    top = anchorRect.top - popoverRect.height - gap;
  }
  if (top < margin) {
    top = margin;
  }

  popover.style.left = `${Math.round(left)}px`;
  popover.style.top = `${Math.round(top)}px`;
}

function closeNotePopover(shouldCommit) {
  if (!state.activeNoteRowId) {
    return;
  }

  if (shouldCommit && elements.noteTextarea) {
    const row = getRowById(state.activeNoteRowId);
    if (row) {
      const nextNote = typeof elements.noteTextarea.value === "string" ? elements.noteTextarea.value : "";
      if (row.note !== nextNote) {
        row.note = nextNote;
        saveCurrentRows();
        updateNoteTriggerState(row);
      }
    }
  }

  if (elements.notePopover) {
    elements.notePopover.hidden = true;
  }

  clearActiveNoteTrigger();
  state.activeNoteRowId = "";
  state.activeNoteAnchor = null;
}

function openNotePopover(rowId, trigger) {
  if (!elements.notePopover || !elements.noteTextarea) {
    return;
  }

  if (state.activeNoteRowId === rowId) {
    closeNotePopover(true);
    return;
  }

  if (state.activeNoteRowId) {
    closeNotePopover(true);
  }

  const row = getRowById(rowId);
  if (!row) {
    return;
  }

  state.activeNoteRowId = row.id;
  state.activeNoteAnchor = trigger;

  elements.noteTextarea.value = row.note || "";
  elements.notePopover.hidden = false;
  setActiveNoteTrigger(trigger);
  positionNotePopover();

  elements.noteTextarea.focus();
  const caret = elements.noteTextarea.value.length;
  elements.noteTextarea.setSelectionRange(caret, caret);
}

function loadDate(dateString) {
  closeNotePopover(true);

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

function handleRowsClick(event) {
  const target = event.target;
  if (!(target instanceof Element)) {
    return;
  }

  const trigger = target.closest("[data-note-trigger]");
  if (!(trigger instanceof HTMLButtonElement)) {
    return;
  }

  const rowId = trigger.dataset.noteTrigger;
  if (!rowId) {
    return;
  }

  openNotePopover(rowId, trigger);
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

function handleDocumentMouseDown(event) {
  if (!state.activeNoteRowId) {
    return;
  }

  const target = event.target;
  if (!(target instanceof Element)) {
    closeNotePopover(true);
    return;
  }

  if (elements.notePopover && elements.notePopover.contains(target)) {
    return;
  }

  if (target.closest("[data-note-trigger]")) {
    return;
  }

  closeNotePopover(true);
}

function handleDocumentKeyDown(event) {
  if (event.key !== "Escape" || !state.activeNoteRowId) {
    return;
  }
  event.preventDefault();
  closeNotePopover(true);
}

function handleNoteCloseClick() {
  closeNotePopover(true);
}

function handleWindowViewportChange() {
  if (!state.activeNoteRowId) {
    return;
  }
  positionNotePopover();
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

  closeNotePopover(true);
  state.rows = buildTemplateRows(state.currentDate);
  saveCurrentRows();
  renderTables();
}

function initialize() {
  document.addEventListener("mousedown", handleDocumentMouseDown);
  document.addEventListener("keydown", handleDocumentKeyDown);
  window.addEventListener("resize", handleWindowViewportChange);
  window.addEventListener("scroll", handleWindowViewportChange, true);

  elements.journalBlocks.addEventListener("click", handleRowsClick);
  elements.journalBlocks.addEventListener("input", handleRowsInput);
  elements.journalBlocks.addEventListener("change", handleRowsInput);
  elements.noteCloseButton.addEventListener("click", handleNoteCloseClick);
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
