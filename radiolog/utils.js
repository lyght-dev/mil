function $(selector, root) {
  const scope = root || document;
  return scope.querySelector(selector);
}

function $$(selector, root) {
  const scope = root || document;
  return Array.from(scope.querySelectorAll(selector));
}

function formatDate(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function getToday() {
  return formatDate(new Date());
}

function isValidDateString(value) {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value);
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

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
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

function isDivisionRow(row) {
  return row.linkType === "사단망";
}

function isPreRow(row) {
  return row.linkType === PRE_LINK_TYPE;
}

function isGeneralContactRow(row) {
  return Boolean(row) && !isPreRow(row);
}

function isNoContactEnabled(row) {
  return isGeneralContactRow(row) && row.isNoContact === true;
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

function getBrigadeSlotTimeValue(lookup, network, slotKey) {
  for (const unit of BRIGADE_UNITS) {
    const row = findRow(lookup, "여단망", network, slotKey, unit);
    if (row) {
      return row.recordedTime || "";
    }
  }
  return "";
}
