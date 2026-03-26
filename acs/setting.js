(() => {
  const $ = id => document.getElementById(id);

  const MODE_EMPTY = "empty";
  const MODE_INFO = "info";
  const MODE_EDIT = "edit";
  const MODE_CREATE = "create";

  let allowedMembers = [];
  let allowedMemberById = new Map();
  let selectedMemberId = "";
  let panelMode = MODE_EMPTY;

  const createRequestError = (status, text) => {
    let data = null;

    if (text) {
      try {
        data = JSON.parse(text);
      } catch {
        data = null;
      }
    }

    const err = new Error(data?.message || `HTTP ${status}`);
    err.status = status;
    err.payload = data;
    return err;
  };

  const fetchText = async (url, options) => {
    const res = await fetch(url, options);
    const text = await res.text();

    if (!res.ok) throw createRequestError(res.status, text);
    return text;
  };

  const fetchJson = async (url, options) => {
    const text = await fetchText(url, options);

    if (!text) return null;

    try {
      return JSON.parse(text);
    } catch {
      return null;
    }
  };

  const showMessage = (text, tone) => {
    if (tone === "error") {
      console.error(text);
      return;
    }

    console.log(text);
  };

  const normalizeMembers = items => {
    if (!Array.isArray(items)) return [];

    return items
      .map(item => {
        const id = String(item?.id || "").trim();
        if (!id) return null;

        return {
          id,
          name: String(item?.name || "").trim(),
          unit: String(item?.unit || "").trim()
        };
      })
      .filter(Boolean);
  };

  const setAllowedMembers = items => {
    allowedMembers = normalizeMembers(items);
    allowedMemberById = new Map(allowedMembers.map(item => [item.id, item]));
  };

  const getSearchQuery = () => String($("stg-search")?.value || "").trim().toLowerCase();

  const getVisibleMembers = () => {
    const query = getSearchQuery();
    if (!query) return [...allowedMembers];

    return allowedMembers.filter(item => {
      const id = String(item?.id || "").toLowerCase();
      const name = String(item?.name || "").toLowerCase();
      const unit = String(item?.unit || "").toLowerCase();
      return id.includes(query) || name.includes(query) || unit.includes(query);
    });
  };

  const createCell = text => {
    const cell = document.createElement("td");
    cell.textContent = text;
    return cell;
  };

  const renderMemberTable = () => {
    const body = $("stg-body");
    if (!body) return;

    const members = getVisibleMembers();
    const frag = document.createDocumentFragment();

    if (members.length === 0) {
      const row = document.createElement("tr");
      const cell = document.createElement("td");

      cell.colSpan = 3;
      cell.className = "empty-cell";
      cell.textContent = getSearchQuery() ? "검색 결과가 없습니다." : "등록된 사용자가 없습니다.";
      row.appendChild(cell);
      frag.appendChild(row);
      body.replaceChildren(frag);
      return;
    }

    for (const member of members) {
      const row = document.createElement("tr");

      row.dataset.id = member.id;
      row.className = "stg-row";
      if (member.id === selectedMemberId) row.classList.add("is-selected");

      row.appendChild(createCell(member.id || "-"));
      row.appendChild(createCell(member.name || "-"));
      row.appendChild(createCell(member.unit || "-"));
      frag.appendChild(row);
    }

    body.replaceChildren(frag);
  };

  const getSelectedMember = () => allowedMemberById.get(String(selectedMemberId || "")) || null;

  const setPanelTitle = text => {
    const title = $("stg-panel-title");
    if (title) title.textContent = text;
  };

  const setFormValues = member => {
    const idInput = $("stg-id");
    const nameInput = $("stg-name");
    const unitInput = $("stg-unit");

    if (!idInput || !nameInput || !unitInput) return;

    if (!member) {
      idInput.value = "";
      nameInput.value = "";
      unitInput.value = "";
      return;
    }

    idInput.value = member.id || "";
    nameInput.value = member.name || "";
    unitInput.value = member.unit || "";
  };

  const setFieldReadonly = (idReadonly, nameReadonly, unitReadonly) => {
    const idInput = $("stg-id");
    const nameInput = $("stg-name");
    const unitInput = $("stg-unit");

    if (idInput) idInput.readOnly = idReadonly;
    if (nameInput) nameInput.readOnly = nameReadonly;
    if (unitInput) unitInput.readOnly = unitReadonly;
  };

  const setButtons = ({ edit, remove, save, cancel, saveText }) => {
    const editButton = $("stg-edit-btn");
    const deleteButton = $("stg-delete-btn");
    const saveButton = $("stg-save-btn");
    const cancelButton = $("stg-cancel-btn");

    if (editButton) editButton.hidden = !edit;
    if (deleteButton) deleteButton.hidden = !remove;
    if (saveButton) {
      saveButton.hidden = !save;
      if (saveText) saveButton.textContent = saveText;
    }
    if (cancelButton) cancelButton.hidden = !cancel;
  };

  const applyPanelMode = () => {
    const member = getSelectedMember();

    if ((panelMode === MODE_INFO || panelMode === MODE_EDIT) && !member) {
      panelMode = MODE_EMPTY;
      selectedMemberId = "";
    }

    if (panelMode === MODE_EMPTY) {
      setPanelTitle("사용자 정보");
      setFormValues(null);
      setFieldReadonly(true, true, true);
      setButtons({ edit: false, remove: false, save: false, cancel: false });
      renderMemberTable();
      return;
    }

    if (panelMode === MODE_INFO) {
      setPanelTitle("사용자 정보");
      setFormValues(member);
      setFieldReadonly(true, true, true);
      setButtons({ edit: true, remove: true, save: false, cancel: false });
      renderMemberTable();
      return;
    }

    if (panelMode === MODE_EDIT) {
      setPanelTitle("사용자 수정");
      setFormValues(member);
      setFieldReadonly(true, false, false);
      setButtons({ edit: false, remove: false, save: true, cancel: true, saveText: "수정 저장" });
      renderMemberTable();
      return;
    }

    setPanelTitle("사용자 추가");
    setFormValues(null);
    setFieldReadonly(false, false, false);
    setButtons({ edit: false, remove: false, save: true, cancel: true, saveText: "사용자 추가" });
    renderMemberTable();
  };

  const enterEmptyMode = () => {
    panelMode = MODE_EMPTY;
    selectedMemberId = "";
    applyPanelMode();
  };

  const enterInfoMode = id => {
    const member = allowedMemberById.get(String(id || ""));
    if (!member) {
      enterEmptyMode();
      return;
    }

    selectedMemberId = member.id;
    panelMode = MODE_INFO;
    applyPanelMode();
  };

  const enterEditMode = () => {
    if (!getSelectedMember()) {
      enterEmptyMode();
      return;
    }

    panelMode = MODE_EDIT;
    applyPanelMode();
    window.setTimeout(() => {
      $("stg-name")?.focus();
    }, 0);
  };

  const enterCreateMode = () => {
    panelMode = MODE_CREATE;
    applyPanelMode();
    window.setTimeout(() => {
      $("stg-id")?.focus();
    }, 0);
  };

  const reloadAllowedMembers = async () => {
    const data = await fetchJson(`/list.json?ts=${Date.now()}`, { cache: "no-store" });
    setAllowedMembers(data);
  };

  const parseFormMember = form => {
    const formData = new FormData(form);
    const id = String(formData.get("id") || "").trim();
    const name = String(formData.get("name") || "").trim();
    const unit = String(formData.get("unit") || "").trim();

    if (!id || !name || !unit) return null;
    return { id, name, unit };
  };

  // API 연동 단계에서 구현할 CRUD 시그니처
  const createMember = async member => ({ status: "pending", action: "create", member });
  const updateMember = async (id, memberPatch) => ({ status: "pending", action: "update", id, memberPatch });
  const deleteMember = async id => ({ status: "pending", action: "delete", id });

  const runCrudAction = async (actionName, task) => {
    try {
      await task();
      showMessage(`${actionName} 요청을 처리했습니다. (API 미연결)`, "warn");
    } catch (err) {
      showMessage(err?.message || `${actionName} 처리에 실패했습니다.`, "error");
    }

    try {
      await reloadAllowedMembers();
    } catch (err) {
      showMessage(err?.message || "allowedMembers 재조회에 실패했습니다.", "error");
    }
  };

  const restorePanelAfterReload = modeBefore => {
    if (modeBefore === MODE_CREATE) {
      panelMode = MODE_CREATE;
      applyPanelMode();
      return;
    }

    if (selectedMemberId && allowedMemberById.has(selectedMemberId)) {
      panelMode = MODE_INFO;
      applyPanelMode();
      return;
    }

    enterEmptyMode();
  };

  const handleFormSubmit = event => {
    event.preventDefault();

    const member = parseFormMember(event.currentTarget);
    if (!member) {
      showMessage("군번, 이름, 소속을 모두 입력해 주세요.", "error");
      return;
    }

    if (panelMode === MODE_EDIT) {
      const targetId = selectedMemberId;
      if (!targetId) {
        showMessage("수정할 사용자를 먼저 선택해 주세요.", "error");
        return;
      }

      void runCrudAction("사용자 수정", () => updateMember(targetId, { name: member.name, unit: member.unit }))
        .then(() => restorePanelAfterReload(MODE_INFO));
      return;
    }

    if (panelMode === MODE_CREATE) {
      void runCrudAction("사용자 추가", () => createMember(member))
        .then(() => restorePanelAfterReload(MODE_CREATE));
    }
  };

  const handleDelete = () => {
    const member = getSelectedMember();
    if (!member) {
      enterEmptyMode();
      return;
    }

    const ok = window.confirm(`${member.id} 사용자를 삭제하시겠습니까?`);
    if (!ok) return;

    const deletedId = member.id;
    void runCrudAction("사용자 삭제", () => deleteMember(deletedId)).then(() => {
      if (allowedMemberById.has(deletedId)) {
        panelMode = MODE_INFO;
        applyPanelMode();
        return;
      }

      enterEmptyMode();
    });
  };

  const handleCancel = () => {
    if (selectedMemberId && allowedMemberById.has(selectedMemberId)) {
      panelMode = MODE_INFO;
      applyPanelMode();
      return;
    }

    enterEmptyMode();
  };

  const bindEvents = () => {
    const form = $("stg-form");
    const search = $("stg-search");
    const reload = $("stg-reload");
    const add = $("stg-add");
    const edit = $("stg-edit-btn");
    const remove = $("stg-delete-btn");
    const cancel = $("stg-cancel-btn");
    const body = $("stg-body");

    form?.addEventListener("submit", handleFormSubmit);

    search?.addEventListener("input", () => {
      renderMemberTable();
    });

    reload?.addEventListener("click", () => {
      const modeBefore = panelMode;
      void reloadAllowedMembers().then(() => {
        restorePanelAfterReload(modeBefore);
      }).catch(err => {
        showMessage(err?.message || "allowedMembers 재조회에 실패했습니다.", "error");
      });
    });

    add?.addEventListener("click", () => {
      enterCreateMode();
    });

    edit?.addEventListener("click", () => {
      enterEditMode();
    });

    remove?.addEventListener("click", () => {
      handleDelete();
    });

    cancel?.addEventListener("click", () => {
      handleCancel();
    });

    body?.addEventListener("click", event => {
      const target = event.target;
      if (!(target instanceof HTMLElement)) return;

      const row = target.closest("tr[data-id]");
      if (!row) return;

      enterInfoMode(row.dataset.id);
    });
  };

  const init = async () => {
    bindEvents();

    try {
      await reloadAllowedMembers();
      enterEmptyMode();
    } catch (err) {
      showMessage(err?.message || "명단을 불러오지 못했습니다.", "error");
      enterEmptyMode();
    }
  };

  void init();
})();
