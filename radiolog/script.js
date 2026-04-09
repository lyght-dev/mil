const STORAGE_DATE_KEY = "radiolog:selectedDate";
const STORAGE_JOURNAL_PREFIX = "radiolog:journal:";
const STORAGE_AUTHOR_PREFIX = "radiolog:author:";
const SIGNAL_OPTIONS = ["", "1/1", "2/2", "3/3"];
const RANK_OPTIONS = ["", "이병", "일병", "상병", "병장"];
const PRE_RECEIVE_STATUS_OPTIONS = ["", "성공", "실패"];
const NO_CONTACT_REASON_OPTIONS = ["중계소 이상", "감명도 저조", "중계소 키물림", "무전실 폐쇄", "기타"];
const NO_CONTACT_REASON_SELECT_OPTIONS = ["", ...NO_CONTACT_REASON_OPTIONS];

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
  { slotKey: "CF-직접입력-1", label: "불시교신", isManualTime: true }
];
const BRIGADE_F_SLOTS = [{ slotKey: "12:00", label: "직접입력", isManualTime: true }];
const CF_MANUAL_SLOT_KEYS = BRIGADE_CF_SLOTS.filter((slot) => slot.isManualTime).map(
  (slot) => slot.slotKey
);

const elements = {
  dateInput: $("#date-input"),
  resetButton: $("#reset-btn"),
  viewButton: $("#view-btn"),
  authorAm: $("#author-am"),
  authorPm: $("#author-pm"),
  journalBlocks: $("#journal-blocks"),
  divisionBody: $("#division-body"),
  divisionPreBody: $("#division-pre-body"),
  brigadeCfBody: $("#brigade-cf-body"),
  brigadeFBody: $("#brigade-f-body"),
  brigadePreBody: $("#brigade-pre-body"),
  notePopover: $("#note-popover"),
  noteTextarea: $("#note-textarea"),
  noteCloseButton: $("#note-close-btn"),
  cellContextMenu: $("#cell-context-menu"),
  cellNoContactAction: $("#cell-no-contact-action")
};

const state = {
  currentDate: "",
  rows: [],
  activeNoteRowId: "",
  activeNoteAnchor: null,
  activeContextRowId: ""
};

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
    isNoContact: false,
    noContactReason: "",
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
    const normalizedNoContactReason = normalizeOptionValue(
      typeof stored.noContactReason === "string" ? stored.noContactReason : "",
      NO_CONTACT_REASON_SELECT_OPTIONS
    );

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
      isNoContact:
        !isPreRow(row) && typeof stored.isNoContact === "boolean" ? stored.isNoContact : false,
      noContactReason: normalizedNoContactReason,
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

  if (isNoContactEnabled(row)) {
    return false;
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

function renderSelectOptions(options, selectedValue) {
  return options
    .map((value) => {
      const selected = value === selectedValue ? ' selected="selected"' : "";
      const label = value || "-";
      return `<option value="${escapeHtml(value)}"${selected}>${escapeHtml(label)}</option>`;
    })
    .join("");
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
              aria-label="근무자 계급"
              data-id="${escapeHtml(row.id)}"
              data-field="counterpartyRank"
            >
              ${renderSelectOptions(RANK_OPTIONS, row.counterpartyRank)}
            </select>
            <input
              class="editor-control"
              aria-label="근무자 성명"
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

function renderNoContactCell(row) {
  return `<td class="matrix-cell">
    <div class="cell-editor pending blocked" data-row-cell="${escapeHtml(row.id)}">
      ${renderNoteTrigger(row)}
      <div class="editor-grid">
        <div class="editor-row">
          <div class="editor-controls">
            <div class="blocked-text">미교신</div>
          </div>
        </div>
        <div class="editor-row">
          <div class="editor-controls">
            <select
              class="editor-control"
              aria-label="미교신 사유"
              data-id="${escapeHtml(row.id)}"
              data-field="noContactReason"
            >
              ${renderSelectOptions(NO_CONTACT_REASON_SELECT_OPTIONS, row.noContactReason)}
            </select>
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

  if (isNoContactEnabled(row)) {
    return renderNoContactCell(row);
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
              aria-label="상대 근무자 계급"
              data-id="${escapeHtml(row.id)}"
              data-field="counterpartyRank"
            >
              ${renderSelectOptions(RANK_OPTIONS, row.counterpartyRank)}
            </select>
            <input
              class="editor-control"
              aria-label="상대 근무자 성명"
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
      const guideCell = renderGuideCell(["교신시각", "송수신 감명도", "근무자"]);
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
        ${renderGuideCell(["수신상태", "근무자"])}
        ${renderPreCell(row)}
      </tr>`;
    })
    .join("");
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
  const guideCell = renderGuideCell(["송수신 감명도", "근무자"]);
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
  const guideCell = renderGuideCell(["수신상태", "근무자"]);
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

function setContextActionLabel(row) {
  if (!(elements.cellNoContactAction instanceof HTMLButtonElement)) {
    return;
  }
  elements.cellNoContactAction.textContent = isNoContactEnabled(row) ? "교신으로 전환" : "미교신 설정";
}

function closeCellContextMenu() {
  if (elements.cellContextMenu) {
    elements.cellContextMenu.hidden = true;
  }
  state.activeContextRowId = "";
}

function positionCellContextMenu(clientX, clientY) {
  if (!elements.cellContextMenu) {
    return;
  }

  const menu = elements.cellContextMenu;
  const margin = 8;
  const rect = menu.getBoundingClientRect();
  let left = clientX;
  let top = clientY;

  if (left + rect.width > window.innerWidth - margin) {
    left = window.innerWidth - margin - rect.width;
  }
  if (top + rect.height > window.innerHeight - margin) {
    top = window.innerHeight - margin - rect.height;
  }
  if (left < margin) {
    left = margin;
  }
  if (top < margin) {
    top = margin;
  }

  menu.style.left = `${Math.round(left)}px`;
  menu.style.top = `${Math.round(top)}px`;
}

function openCellContextMenu(row, clientX, clientY) {
  if (!elements.cellContextMenu || !isGeneralContactRow(row)) {
    return;
  }

  state.activeContextRowId = row.id;
  setContextActionLabel(row);
  elements.cellContextMenu.hidden = false;
  positionCellContextMenu(clientX, clientY);
}

function toggleNoContact(row) {
  if (!isGeneralContactRow(row)) {
    return;
  }

  if (isNoContactEnabled(row)) {
    row.isNoContact = false;
    row.noContactReason = "";
  } else {
    row.isNoContact = true;
    if (!NO_CONTACT_REASON_SELECT_OPTIONS.includes(row.noContactReason)) {
      row.noContactReason = "";
    }
  }

  saveCurrentRows();
  renderTables();
}

function findContextTargetRow(target) {
  if (!(target instanceof Element)) {
    return null;
  }
  const cell = target.closest("[data-row-cell]");
  if (!cell || !(cell instanceof HTMLElement)) {
    return null;
  }
  const rowId = cell.dataset.rowCell;
  if (!rowId) {
    return null;
  }
  const row = getRowById(rowId);
  if (!isGeneralContactRow(row)) {
    return null;
  }
  return row;
}

function findNoteTriggerButton(rowId) {
  const triggers = $$("[data-note-trigger]");
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
  closeCellContextMenu();
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
  const cells = $$("[data-row-cell]");
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
  cell.classList.toggle("blocked", isNoContactEnabled(row));
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

  if (field === "noContactReason") {
    row.noContactReason = normalizeOptionValue(value, NO_CONTACT_REASON_SELECT_OPTIONS);
    saveCurrentRows();
    syncCellState(row);
    return;
  }

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

  closeCellContextMenu();

  const rowId = trigger.dataset.noteTrigger;
  if (!rowId) {
    return;
  }

  openNotePopover(rowId, trigger);
}

function handleRowsContextMenu(event) {
  const row = findContextTargetRow(event.target);
  if (!row) {
    closeCellContextMenu();
    return;
  }

  event.preventDefault();
  closeNotePopover(true);
  openCellContextMenu(row, event.clientX, event.clientY);
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
  const target = event.target;
  if (!(target instanceof Element)) {
    closeCellContextMenu();
    closeNotePopover(true);
    return;
  }

  if (state.activeContextRowId && elements.cellContextMenu && !elements.cellContextMenu.contains(target)) {
    closeCellContextMenu();
  }

  if (!state.activeNoteRowId) {
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
  if (event.key !== "Escape") {
    return;
  }

  if (!state.activeNoteRowId && !state.activeContextRowId) {
    return;
  }

  event.preventDefault();
  closeCellContextMenu();
  closeNotePopover(true);
}

function handleNoteCloseClick() {
  closeNotePopover(true);
}

function handleWindowViewportChange() {
  closeCellContextMenu();

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

function handleViewModeClick() {
  window.open("/view", "_blank");
}

function handleResetClick() {
  const ok = window.confirm("해당 날짜 일지를 기본 양식으로 다시 생성합니다.");
  if (!ok) {
    return;
  }

  closeCellContextMenu();
  closeNotePopover(true);
  state.rows = buildTemplateRows(state.currentDate);
  saveCurrentRows();
  renderTables();
}

function handleCellContextActionClick() {
  if (!state.activeContextRowId) {
    return;
  }
  const row = getRowById(state.activeContextRowId);
  if (!row) {
    closeCellContextMenu();
    return;
  }
  toggleNoContact(row);
  closeCellContextMenu();
}

function initialize() {
  document.addEventListener("mousedown", handleDocumentMouseDown);
  document.addEventListener("keydown", handleDocumentKeyDown);
  window.addEventListener("resize", handleWindowViewportChange);
  window.addEventListener("scroll", handleWindowViewportChange, true);

  elements.journalBlocks.addEventListener("click", handleRowsClick);
  elements.journalBlocks.addEventListener("contextmenu", handleRowsContextMenu);
  elements.journalBlocks.addEventListener("input", handleRowsInput);
  elements.journalBlocks.addEventListener("change", handleRowsInput);
  elements.noteCloseButton.addEventListener("click", handleNoteCloseClick);
  elements.cellNoContactAction.addEventListener("click", handleCellContextActionClick);
  elements.authorAm.addEventListener("input", handleAuthorInput);
  elements.authorPm.addEventListener("input", handleAuthorInput);
  elements.dateInput.addEventListener("change", handleDateChange);
  elements.resetButton.addEventListener("click", handleResetClick);
  elements.viewButton.addEventListener("click", handleViewModeClick);

  const savedDate = localStorage.getItem(STORAGE_DATE_KEY);
  const initialDate = savedDate || getToday();
  loadDate(initialDate);
}

if (
  elements.dateInput &&
  elements.resetButton &&
  elements.viewButton &&
  elements.authorAm &&
  elements.authorPm &&
  elements.journalBlocks &&
  elements.divisionBody &&
  elements.divisionPreBody &&
  elements.brigadeCfBody &&
  elements.brigadeFBody &&
  elements.brigadePreBody &&
  elements.notePopover &&
  elements.noteTextarea &&
  elements.noteCloseButton &&
  elements.cellContextMenu &&
  elements.cellNoContactAction
) {
  initialize();
}
