const viewElements = {
  dateValue: document.querySelector("#view-date-value"),
  authorAm: document.querySelector("#view-author-am"),
  authorPm: document.querySelector("#view-author-pm"),
  emptyPanel: document.querySelector("#view-empty"),
  emptyDetail: document.querySelector("#view-empty-detail"),
  journalBlocks: document.querySelector("#view-journal-blocks"),
  divisionBody: document.querySelector("#view-division-body"),
  divisionPreBody: document.querySelector("#view-division-pre-body"),
  brigadeCfBody: document.querySelector("#view-brigade-cf-body"),
  brigadeFBody: document.querySelector("#view-brigade-f-body"),
  brigadePreBody: document.querySelector("#view-brigade-pre-body")
};

function isValidDateString(value) {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value);
}

function getViewDate() {
  const savedDate = localStorage.getItem(STORAGE_DATE_KEY);
  if (isValidDateString(savedDate)) {
    return savedDate;
  }
  return getToday();
}

function hasDisplayText(value) {
  return typeof value === "string" && value.trim() !== "";
}

function displayText(value) {
  if (!hasDisplayText(value)) {
    return "-";
  }
  return value;
}

function renderLine(label, value) {
  return `<div class="view-line">
    <span class="view-key">${escapeHtml(label)}</span>
    <span class="view-value">${escapeHtml(displayText(value))}</span>
  </div>`;
}

function renderCounterparty(row) {
  const rank = hasDisplayText(row.counterpartyRank) ? row.counterpartyRank : "";
  const name = hasDisplayText(row.counterpartyName) ? row.counterpartyName : "";

  if (rank && name) {
    return `${rank} ${name}`;
  }

  return rank || name || "";
}

function renderViewGeneralCell(row) {
  if (!row) {
    return '<td class="matrix-cell"><div class="view-cell">-</div></td>';
  }

  const lines = [];

  if (requiresRecordedTime(row)) {
    lines.push(renderLine("교신시각", row.recordedTime));
  }

  if (isNoContactEnabled(row)) {
    lines.push(renderLine("상태", "미교신"));
    lines.push(renderLine("사유", row.noContactReason));
  } else {
    lines.push(renderLine("송신", row.txSignal));
    lines.push(renderLine("수신", row.rxSignal));
    lines.push(renderLine("교신자", renderCounterparty(row)));
  }

  if (hasDisplayText(row.note)) {
    lines.push(renderLine("비고", row.note));
  }

  return `<td class="matrix-cell"><div class="view-cell">${lines.join("")}</div></td>`;
}

function renderViewPreCell(row) {
  if (!row) {
    return '<td class="matrix-cell"><div class="view-cell">-</div></td>';
  }

  const lines = [
    renderLine("수신상태", row.preReceiveStatus),
    renderLine("보고자", renderCounterparty(row))
  ];

  if (hasDisplayText(row.note)) {
    lines.push(renderLine("비고", row.note));
  }

  return `<td class="matrix-cell"><div class="view-cell">${lines.join("")}</div></td>`;
}

function renderDivisionViewRows(lookup, showNoteGuide) {
  viewElements.divisionBody.innerHTML = DIVISION_SLOTS.map((slotLabel) => {
    const guideCell = renderGuideCell([
      "교신시각",
      "송수신 감명도",
      showNoteGuide ? "교신자/비고" : "교신자"
    ]);
    const cells = DIVISION_NETWORKS.map((network) => {
      const row = findRow(lookup, "사단망", network, slotLabel, "1DIV");
      return renderViewGeneralCell(row);
    }).join("");

    return `<tr>
      <th class="row-label" scope="row">${escapeHtml(slotLabel)}</th>
      ${guideCell}
      ${cells}
    </tr>`;
  }).join("");
}

function renderDivisionPreViewRows(lookup, showNoteGuide) {
  const guideLabels = showNoteGuide ? ["수신상태", "보고자", "비고"] : ["수신상태", "보고자"];

  viewElements.divisionPreBody.innerHTML = PRE_SLOTS.map((slotLabel) => {
    const row = findRow(lookup, PRE_LINK_TYPE, DIVISION_PRE_NETWORK, slotLabel, "1DIV");
    return `<tr>
      <th class="row-label" scope="row">${escapeHtml(slotLabel)}</th>
      ${renderGuideCell(guideLabels)}
      ${renderViewPreCell(row)}
    </tr>`;
  }).join("");
}

function renderBrigadeViewSlotLabel(lookup, network, slot) {
  if (!slot.isManualTime) {
    return escapeHtml(slot.label);
  }

  const value = getBrigadeSlotTimeValue(lookup, network, slot.slotKey);

  return `<div class="view-slot-label">
    <span>${escapeHtml(slot.label)}</span>
    <span class="view-slot-time">${escapeHtml(displayText(value))}</span>
  </div>`;
}

function renderBrigadeViewRows(lookup, network, slots, bodyElement, showNoteGuide) {
  const guideCell = renderGuideCell(
    showNoteGuide ? ["송수신 감명도", "교신자", "비고"] : ["송수신 감명도", "교신자"]
  );

  bodyElement.innerHTML = slots.map((slot) => {
    const cells = BRIGADE_UNITS.map((unit) => {
      const row = findRow(lookup, "여단망", network, slot.slotKey, unit);
      return renderViewGeneralCell(row);
    }).join("");

    return `<tr>
      <th class="row-label" scope="row">${renderBrigadeViewSlotLabel(lookup, network, slot)}</th>
      ${guideCell}
      ${cells}
    </tr>`;
  }).join("");
}

function renderBrigadePreViewRows(lookup, showNoteGuide) {
  const guideCell = renderGuideCell(
    showNoteGuide ? ["수신상태", "보고자", "비고"] : ["수신상태", "보고자"]
  );

  viewElements.brigadePreBody.innerHTML = PRE_SLOTS.map((slotLabel) => {
    const cells = BRIGADE_UNITS.map((unit) => {
      const row = findRow(lookup, PRE_LINK_TYPE, BRIGADE_PRE_NETWORK, slotLabel, unit);
      return renderViewPreCell(row);
    }).join("");

    return `<tr>
      <th class="row-label" scope="row">${escapeHtml(slotLabel)}</th>
      ${guideCell}
      ${cells}
    </tr>`;
  }).join("");
}

function renderViewTables(rows) {
  const lookup = createRowLookup(rows);
  const showNoteGuide = rows.some((row) => hasDisplayText(row.note));
  renderDivisionViewRows(lookup, showNoteGuide);
  renderDivisionPreViewRows(lookup, showNoteGuide);
  renderBrigadeViewRows(lookup, "CF", BRIGADE_CF_SLOTS, viewElements.brigadeCfBody, showNoteGuide);
  renderBrigadeViewRows(lookup, "F", BRIGADE_F_SLOTS, viewElements.brigadeFBody, showNoteGuide);
  renderBrigadePreViewRows(lookup, showNoteGuide);
}

function setViewMeta(dateString) {
  const author = readStoredAuthors(dateString);
  viewElements.dateValue.textContent = dateString;
  viewElements.authorAm.textContent = displayText(author.am);
  viewElements.authorPm.textContent = displayText(author.pm);
}

function showNoData(dateString) {
  setViewMeta(dateString);
  viewElements.emptyPanel.hidden = false;
  viewElements.journalBlocks.hidden = true;
  viewElements.emptyDetail.textContent = `${dateString} 기준 저장된 일지가 없습니다.`;
}

function showJournal(dateString, rows) {
  setViewMeta(dateString);
  renderViewTables(rows);
  viewElements.emptyPanel.hidden = true;
  viewElements.journalBlocks.hidden = false;
}

function initializeView() {
  if (
    !viewElements.dateValue ||
    !viewElements.authorAm ||
    !viewElements.authorPm ||
    !viewElements.emptyPanel ||
    !viewElements.emptyDetail ||
    !viewElements.journalBlocks ||
    !viewElements.divisionBody ||
    !viewElements.divisionPreBody ||
    !viewElements.brigadeCfBody ||
    !viewElements.brigadeFBody ||
    !viewElements.brigadePreBody
  ) {
    return;
  }

  const dateString = getViewDate();
  const storedRows = readStoredRows(dateString);

  if (!storedRows) {
    showNoData(dateString);
    return;
  }

  const rows = normalizeRows(dateString, storedRows);
  showJournal(dateString, rows);
}

initializeView();
