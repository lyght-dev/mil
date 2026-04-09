const viewElements = {
  dateValue: $("#view-date-value"),
  authorAm: $("#view-author-am"),
  authorPm: $("#view-author-pm"),
  printDateValue: $("#print-view-date-value"),
  printAuthorAm: $("#print-view-author-am"),
  printAuthorPm: $("#print-view-author-pm"),
  emptyPanel: $("#view-empty"),
  emptyDetail: $("#view-empty-detail"),
  journalBlocks: $("#view-journal-blocks"),
  divisionBody: $("#view-division-body"),
  divisionPreBody: $("#view-division-pre-body"),
  brigadeCfBody: $("#view-brigade-cf-body"),
  brigadeFBody: $("#view-brigade-f-body"),
  brigadeCipherBody: $("#view-brigade-cipher-body"),
  brigadePreBody: $("#view-brigade-pre-body")
};

function getViewDate() {
  const savedDate = localStorage.getItem(STORAGE_DATE_KEY);
  if (isValidDateString(savedDate)) {
    return savedDate;
  }
  return getToday();
}

function renderLine(value) {
  return `<div class="view-line">
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

function renderSignalPair(row) {
  const tx = hasDisplayText(row.txSignal) ? row.txSignal : "-";
  const rx = hasDisplayText(row.rxSignal) ? row.rxSignal : "-";
  if (tx === "-" && rx === "-") {
    return "-";
  }
  return `${tx} / ${rx}`;
}

function renderViewGeneralCell(row) {
  if (!row) {
    return '<td class="matrix-cell"><div class="view-cell">-</div></td>';
  }

  const lines = [];

  if (row.linkType === "사단망" && requiresRecordedTime(row)) {
    lines.push(renderLine(row.recordedTime));
  }

  if (isNoContactEnabled(row)) {
    lines.push(renderLine("미교신"));
    lines.push(renderLine(row.noContactReason));
  } else {
    lines.push(renderLine(renderSignalPair(row)));
    lines.push(renderLine(renderCounterparty(row)));
  }

  if (hasDisplayText(row.note)) {
    lines.push(renderLine(row.note));
  }

  return `<td class="matrix-cell"><div class="view-cell">${lines.join("")}</div></td>`;
}

function renderViewPreCell(row) {
  if (!row) {
    return '<td class="matrix-cell"><div class="view-cell">-</div></td>';
  }

  const lines = [
    renderLine(row.preReceiveStatus),
    renderLine(renderCounterparty(row))
  ];

  if (hasDisplayText(row.note)) {
    lines.push(renderLine(row.note));
  }

  return `<td class="matrix-cell"><div class="view-cell">${lines.join("")}</div></td>`;
}

function renderCipherUnits(row) {
  return row.cipherUnit;
}

function renderCipherTimeRange(row) {
  const start = hasDisplayText(row.cipherStartTime) ? row.cipherStartTime : "-";
  const end = hasDisplayText(row.cipherEndTime) ? row.cipherEndTime : "-";
  if (start === "-" && end === "-") {
    return "-";
  }
  return `${start} ~ ${end}`;
}

function renderViewCipherCell(row) {
  if (!row) {
    return '<td class="matrix-cell"><div class="view-cell">-</div></td>';
  }

  const lines = [
    renderLine(renderCipherUnits(row)),
    renderLine(renderCounterparty(row)),
    renderLine(row.cipherWordCount),
    renderLine(renderCipherTimeRange(row))
  ];

  if (hasDisplayText(row.note)) {
    lines.push(renderLine(row.note));
  }

  return `<td class="matrix-cell"><div class="view-cell">${lines.join("")}</div></td>`;
}

function renderDivisionViewRows(lookup, showNoteGuide) {
  viewElements.divisionBody.innerHTML = DIVISION_SLOTS.map((slotLabel) => {
    const guideCell = renderGuideCell([
      "교신시각",
      "송수신 감명도",
      showNoteGuide ? "근무자/비고" : "근무자"
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
  const guideLabels = showNoteGuide ? ["수신상태", "근무자", "비고"] : ["수신상태", "근무자"];

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
    showNoteGuide ? ["송수신 감명도", "근무자", "비고"] : ["송수신 감명도", "근무자"]
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

function renderBrigadeCipherViewRows(lookup, showNoteGuide) {
  const guideLabels = showNoteGuide
    ? ["대대", "근무자", "어수", "시작~종료", "비고"]
    : ["대대", "근무자", "어수", "시작~종료"];
  const cells = BRIGADE_CIPHER_SLOTS.map((slotLabel) => {
    const row = findRow(lookup, CIPHER_LINK_TYPE, BRIGADE_CIPHER_NETWORK, slotLabel, "여단");
    return renderViewCipherCell(row);
  }).join("");

  viewElements.brigadeCipherBody.innerHTML = `<tr>
    <th class="row-label" scope="row">음어</th>
    ${renderGuideCell(guideLabels)}
    ${cells}
  </tr>`;
}

function renderBrigadePreViewRows(lookup, showNoteGuide) {
  const guideCell = renderGuideCell(
    showNoteGuide ? ["수신상태", "근무자", "비고"] : ["수신상태", "근무자"]
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
  renderBrigadeCipherViewRows(lookup, showNoteGuide);
  renderBrigadePreViewRows(lookup, showNoteGuide);
}

function setViewMeta(dateString) {
  const author = readStoredAuthors(dateString);
  viewElements.dateValue.textContent = dateString;
  viewElements.authorAm.textContent = displayText(author.am);
  viewElements.authorPm.textContent = displayText(author.pm);
  if (viewElements.printDateValue) {
    viewElements.printDateValue.textContent = dateString;
  }
  if (viewElements.printAuthorAm) {
    viewElements.printAuthorAm.textContent = displayText(author.am);
  }
  if (viewElements.printAuthorPm) {
    viewElements.printAuthorPm.textContent = displayText(author.pm);
  }
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
    !viewElements.brigadeCipherBody ||
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
