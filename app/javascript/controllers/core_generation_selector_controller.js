import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "lotSelect",
    "preview",
    "hiddenFields",
    "section",
    "selectorsPanel",
    "quickCreatePanel",
    "quickCreateStatus",
    "quickLotNumber",
    "quickPlant",
    "quickMixType",
    "quickNumSublots",
    "quickLanesPerSublot",
    "quickLaneLength",
    "quickLaneWidth",
    "quickCreateButton",
    "postCreateActions",
    "generationPanel",
    "generationSeed",
    "generationMatCores",
    "generationJointCores",
    "generationRounding",
    "generationMatBuffer",
    "generationLaneBuffer",
    "generationCreateButton",
    "generationStatus",
    "lotPanel",
    "lotPanelStatus",
    "lotPanelContent",
    "coreTab",
    "coreTabPanel",
    "previewActions",
    "lockSummary",
    "lockCoresButton",
    "exportCsvButton",
    "exportXlsxButton",
    "manageLotLink"
  ]

  static values = {
    projectId: Number,
    asphaltChecklistSelected: Boolean
  }

  connect() {
    this.previewLocations = []
    this.availableGenerations = []
    this.currentGeneration = null
    this.currentLotLockState = null
    this.lotGenerationDefaultsByLot = {}
    this.laneDraftCounter = 0

    this.boundChecklistHandler = (event) => this.checklistsChanged(event)
    document.addEventListener("spec-checklists:changed", this.boundChecklistHandler)

    this.boundLotPanelClick = (event) => this.handleLotPanelClick(event)
    this.boundLotPanelInput = (event) => this.handleLotPanelInput(event)
    if (this.hasLotPanelContentTarget) {
      this.lotPanelContentTarget.addEventListener("click", this.boundLotPanelClick)
      this.lotPanelContentTarget.addEventListener("input", this.boundLotPanelInput)
    }

    this.updateVisibility()

    this.selectFirstLotIfAvailable()

    const lotId = this.currentLotId()
    if (lotId) {
      this.fetchGenerations(lotId)
      this.ensureSelectedLotStatusMessage()
    } else {
      this.generationChanged()
    }
  }

  disconnect() {
    document.removeEventListener("spec-checklists:changed", this.boundChecklistHandler)

    if (this.hasLotPanelContentTarget && this.boundLotPanelClick) {
      this.lotPanelContentTarget.removeEventListener("click", this.boundLotPanelClick)
      this.lotPanelContentTarget.removeEventListener("input", this.boundLotPanelInput)
    }
  }

  checklistsChanged(event) {
    const codes = Array.isArray(event.detail?.codes) ? event.detail.codes : []
    this.applyChecklistCodes(codes)
  }

  refreshChecklistStateFromDom() {
    const list = document.getElementById("active-checklists-list")
    if (!list) {
      this.updateVisibility()
      return
    }

    const codes = Array.from(list.querySelectorAll(".gallery-card[data-spec-code]"))
      .map((card) => (card.dataset.specCode || "").toUpperCase().trim())
      .filter((code) => code.length > 0)

    this.applyChecklistCodes(codes)
  }

  applyChecklistCodes(codes) {
    const asphaltCodes = ["P-401", "P-403"]
    this.asphaltChecklistSelectedValue = codes.some((code) => asphaltCodes.includes(code))
    this.prefillMixType(codes)
    this.updateVisibility()
  }

  prefillMixType(codes) {
    if (!this.hasQuickMixTypeTarget || this.quickMixTypeTarget.value) return
    if (codes.includes("P-401")) {
      this.quickMixTypeTarget.value = "P-401"
      return
    }

    if (codes.includes("P-403")) {
      this.quickMixTypeTarget.value = "P-403"
    }
  }

  lotChanged() {
    const lotId = this.lotSelectTarget.value
    this.currentLotLockState = null

    this.closeInlinePanels()

    if (!lotId) {
      this.clearGenerations()
      this.updateLockControls()
      this.renderQuickStatus("Select a lot to generate cores or manage lot details.", "info")
      return
    }

    this.updateHiddenFields([])
    this.clearPreview()
    this.renderGenerationStatus("")
    this.renderLotPanelStatus("")

    const label = this.selectedLotOptionText()
    if (label) {
      this.renderQuickStatus(`${label} selected. Generate core locations next.`, "success")
    }

    this.fetchGenerations(lotId)
  }

  async createLotAndSublots() {
    if (!this.hasQuickLotNumberTarget || !this.hasQuickCreateStatusTarget) return

    const lotNumber = this.quickLotNumberTarget.value.trim()
    if (!lotNumber) {
      this.renderQuickStatus("Lot number is required.", "error")
      return
    }

    const payload = {
      asphalt_lot: {
        lot_number: lotNumber,
        plant: this.hasQuickPlantTarget ? this.quickPlantTarget.value : "",
        mix_type: this.hasQuickMixTypeTarget ? this.quickMixTypeTarget.value : ""
      },
      quick_setup: {
        num_sublots: this.hasQuickNumSublotsTarget ? this.quickNumSublotsTarget.value : "1",
        lanes_per_sublot: this.hasQuickLanesPerSublotTarget ? this.quickLanesPerSublotTarget.value : "2",
        lane_length_ft: this.hasQuickLaneLengthTarget ? this.quickLaneLengthTarget.value : "500",
        lane_width_ft: this.hasQuickLaneWidthTarget ? this.quickLaneWidthTarget.value : "12"
      }
    }

    this.setQuickCreateButtonState(true)
    this.renderQuickStatus("Creating asphalt lot...", "info")

    try {
      const response = await fetch(`/projects/${this.projectIdValue}/asphalt_lots`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken()
        },
        body: JSON.stringify(payload)
      })

      const data = await response.json()
      if (!response.ok) {
        const errors = Array.isArray(data.errors) ? data.errors.join(" ") : "Unable to create asphalt lot."
        throw new Error(errors)
      }

      this.addLotOption(data.lot)
      this.lotSelectTarget.value = String(data.lot.id)
      this.quickLotNumberTarget.value = ""
      this.renderQuickStatus(
        `Lot ${data.lot.lot_number} created with ${data.lot.sublots_count} sublots. Generate core locations next.`,
        "success"
      )

      this.updateVisibility()
      this.showCoreTab("overview")
      this.lotChanged()
    } catch (error) {
      this.renderQuickStatus(error.message || "Unable to create asphalt lot.", "error")
    } finally {
      this.setQuickCreateButtonState(false)
    }
  }

  async fetchGenerations(lotId) {
    try {
      const url = `/projects/${this.projectIdValue}/asphalt_lots/${lotId}/core_generations_json`
      const response = await fetch(url, {
        headers: { "Accept": "application/json" }
      })

      if (!response.ok) throw new Error("Failed to fetch")

      const data = await response.json()
      this.currentLotLockState = data.lock_state || null
      this.renderGenerations(data.generations)
      return data.generations
    } catch (e) {
      console.error("Error fetching core generations:", e)
      this.currentLotLockState = null
      this.availableGenerations = []
      this.currentGeneration = null
      this.updateHiddenFields([])
      this.renderMessage("Error loading generations.")
      this.updateLockControls()
      return []
    }
  }

  renderGenerations(generations) {
    this.availableGenerations = Array.isArray(generations) ? generations : []

    if (this.availableGenerations.length === 0) {
      this.currentGeneration = null
      this.previewLocations = []
      this.renderMessage("No core locations have been generated for this lot yet.")
      this.updateHiddenFields([])
      this.updatePreviewActions()
      return
    }

    this.selectGeneration(this.availableGenerations[0].id)
  }

  generationChanged() {
    if (!this.hasPreviewTarget) return

    if (!this.currentGeneration) {
      this.previewLocations = []
      this.clearPreview()
      this.updateHiddenFields([])
      this.updatePreviewActions()
      return
    }

    const locations = Array.isArray(this.currentGeneration.locations) ? this.currentGeneration.locations : []
    this.previewLocations = locations
    this.updateHiddenFields([this.currentGeneration.id])
    this.renderPreview(locations)
    this.updatePreviewActions()
  }

  renderPreview(locations) {
    if (locations.length === 0) {
      this.renderMessage("No core locations in this generation.")
      this.updatePreviewActions()
      return
    }

    const table = document.createElement("table")
    table.className = "modern-table table-compact"

    const thead = document.createElement("thead")
    const headRow = document.createElement("tr")
    ;["Mark", "Type", "Sublot", "Lane", "Station (ft)", "Offset (ft)"].forEach((label) => {
      const th = document.createElement("th")
      th.textContent = label
      headRow.appendChild(th)
    })
    thead.appendChild(headRow)

    const tbody = document.createElement("tbody")
    locations.forEach((loc) => {
      const row = document.createElement("tr")
      row.appendChild(this.buildCell(loc.mark, "font-bold"))
      row.appendChild(this.buildCell(loc.core_type))
      row.appendChild(this.buildCell(loc.sublot || "-"))
      row.appendChild(this.buildCell(loc.lane || "-"))
      row.appendChild(this.buildCell(loc.station_ft || "-", "code-font"))
      row.appendChild(this.buildCell(loc.offset_ft || "-", "code-font"))
      tbody.appendChild(row)
    })

    table.appendChild(thead)
    table.appendChild(tbody)

    this.previewTarget.replaceChildren(table)
    this.updatePreviewActions()
  }

  updateHiddenFields(generationIds = []) {
    if (!this.hasHiddenFieldsTarget) return

    const container = this.hiddenFieldsTarget
    container.replaceChildren()

    generationIds.forEach((genId) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "report[core_generation_ids][]"
      input.value = genId
      container.appendChild(input)
    })
  }

  clearGenerations() {
    this.availableGenerations = []
    this.currentGeneration = null
    this.previewLocations = []
    this.clearPreview()
    this.updateHiddenFields([])
    this.updateVisibility()
  }

  clearPreview() {
    if (!this.hasPreviewTarget) return
    this.previewTarget.replaceChildren()
    this.updatePreviewActions()
  }

  renderMessage(message) {
    if (!this.hasPreviewTarget) return

    const paragraph = document.createElement("p")
    paragraph.className = "text-muted"
    paragraph.textContent = message
    this.previewTarget.replaceChildren(paragraph)
    this.updatePreviewActions()
  }

  updatePreviewActions() {
    if (!this.hasPreviewActionsTarget) return

    const hasRows = this.previewLocations.length > 0
    this.previewActionsTarget.classList.toggle("d-none", !hasRows)

    if (!hasRows) return
    this.updateLockControls()
  }

  updateLockControls() {
    if (!this.hasLockCoresButtonTarget) return

    const state = this.currentLotLockState || {}
    const totalSublots = Number(state.total_sublots || 0)
    const lockedSublots = Number(state.locked_sublots || 0)
    const allLocked = !!state.all_locked
    const anyLocked = !!state.any_locked

    if (totalSublots <= 0) {
      this.lockCoresButtonTarget.disabled = true
      this.lockCoresButtonTarget.textContent = "Lock Cores In Place"
      if (this.hasLockSummaryTarget) this.lockSummaryTarget.textContent = "No sublots available to lock."
      return
    }

    this.lockCoresButtonTarget.disabled = false
    this.lockCoresButtonTarget.textContent = allLocked ? "Unlock Cores" : "Lock Cores In Place"

    if (this.hasLockSummaryTarget) {
      const status = anyLocked ? `${lockedSublots} of ${totalSublots} sublots locked.` : `0 of ${totalSublots} sublots locked.`
      this.lockSummaryTarget.textContent = status
    }
  }

  async toggleCoreLockInPlace(event) {
    const button = event.currentTarget
    const lotId = this.currentLotId()
    if (!lotId) return

    const state = this.currentLotLockState || {}
    const totalSublots = Number(state.total_sublots || 0)
    if (totalSublots <= 0) {
      this.renderQuickStatus("Add sublots before locking core locations.", "error")
      return
    }

    const shouldLock = !state.all_locked
    const originalLabel = button.textContent
    button.disabled = true
    button.textContent = shouldLock ? "Locking..." : "Unlocking..."

    try {
      const data = await this.requestJson(
        `/projects/${this.projectIdValue}/asphalt_lots/${lotId}/set_core_lock`,
        {
          method: "PATCH",
          body: { locked: shouldLock }
        }
      )

      this.currentLotLockState = data.lock_state || this.currentLotLockState
      this.renderQuickStatus(data.message || "Core lock state updated.", "success")
      this.renderLotPanelStatus("Sublot lock state updated.", "success")
    } catch (error) {
      this.renderQuickStatus(error.message || "Unable to update core lock state.", "error")
    } finally {
      button.disabled = false
      button.textContent = originalLabel
      this.updateLockControls()
    }
  }

  exportPreviewCsv() {
    if (this.previewLocations.length === 0) return

    const headers = ["Mark", "Type", "Sublot", "Lane", "Station (ft)", "Offset (ft)"]
    const rows = this.previewLocations.map((loc) => [
      loc.mark ?? "-",
      loc.core_type ?? "-",
      loc.sublot ?? "-",
      loc.lane ?? "-",
      loc.station_ft ?? "-",
      loc.offset_ft ?? "-"
    ])

    const lines = [headers, ...rows].map((row) => row.map((value) => this.escapeCsv(value)).join(","))
    const csvContent = `${lines.join("\n")}\n`
    const blob = new Blob([csvContent], { type: "text/csv;charset=utf-8" })

    const lotLabel = this.selectedLotOptionText()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "") || "asphalt-lot"
    const timestamp = new Date().toISOString().slice(0, 19).replace(/[T:]/g, "-")
    const fileName = `${lotLabel}-core-locations-${timestamp}.csv`

    this.downloadBlob(blob, fileName)
    this.renderQuickStatus("Core location CSV downloaded.", "success")
  }

  exportPreviewXlsx() {
    const lotId = this.currentLotId()
    const generationId = this.currentGeneration?.id
    if (!lotId || !generationId) return

    const url = `/projects/${this.projectIdValue}/asphalt_lots/${lotId}/core_generations/${generationId}/export_xlsx`
    window.location.href = url
    this.renderQuickStatus("Generating Excel export...", "info")
  }

  escapeCsv(value) {
    const stringValue = String(value ?? "")
    if (!/[",\n]/.test(stringValue)) return stringValue
    return `"${stringValue.replace(/"/g, '""')}"`
  }

  downloadBlob(blob, fileName) {
    const url = window.URL.createObjectURL(blob)
    const link = document.createElement("a")
    link.href = url
    link.download = fileName
    document.body.appendChild(link)
    link.click()
    link.remove()
    window.URL.revokeObjectURL(url)
  }

  buildCell(value, className = "") {
    const td = document.createElement("td")
    td.textContent = value
    if (className) td.className = className
    return td
  }

  updateVisibility() {
    if (!this.hasSectionTarget) return

    const hasLots = this.hasSelectableLots()
    const shouldShowSection = this.asphaltChecklistSelectedValue

    this.sectionTarget.classList.toggle("d-none", !shouldShowSection)

    if (this.hasSelectorsPanelTarget) {
      this.selectorsPanelTarget.classList.toggle("d-none", !hasLots)
    }

    if (this.hasQuickCreatePanelTarget) {
      this.quickCreatePanelTarget.classList.toggle("d-none", false)
    }

    if (this.hasPostCreateActionsTarget) {
      this.postCreateActionsTarget.classList.toggle("d-none", hasLots)
    }

    if (this.hasCoreTabTarget) {
      const defaultTab = hasLots ? "overview" : "setup"
      this.showCoreTab(defaultTab)
    }
  }

  hasSelectableLots() {
    if (!this.hasLotSelectTarget) return false

    return Array.from(this.lotSelectTarget.options).some((option) => {
      return option.value && !option.disabled
    })
  }

  addLotOption(lot) {
    const existingOption = Array.from(this.lotSelectTarget.options).find((option) => option.value === String(lot.id))
    if (existingOption) {
      existingOption.textContent = this.lotOptionText(lot)
      return
    }

    const option = document.createElement("option")
    option.value = String(lot.id)
    option.textContent = this.lotOptionText(lot)
    this.lotSelectTarget.appendChild(option)
  }

  removeLotOption(lotId) {
    if (!this.hasLotSelectTarget) return

    const option = Array.from(this.lotSelectTarget.options).find((item) => item.value === String(lotId))
    if (option) option.remove()
  }

  lotOptionText(lot) {
    const plant = lot.plant ? `${lot.plant} ` : ""
    return `${plant}Lot ${lot.lot_number}${lot.mix_type ? ` - ${lot.mix_type}` : ""}`
  }

  setQuickCreateButtonState(isLoading) {
    if (!this.hasQuickCreateButtonTarget) return
    this.quickCreateButtonTarget.disabled = isLoading
    this.quickCreateButtonTarget.textContent = isLoading ? "Creating..." : "Create Lot and Sublots"
  }

  setGenerationButtonState(isLoading) {
    if (!this.hasGenerationCreateButtonTarget) return
    this.generationCreateButtonTarget.disabled = isLoading
    this.generationCreateButtonTarget.textContent = isLoading ? "Generating..." : "Generate All Locations"
  }

  renderQuickStatus(message, state = "info") {
    if (!this.hasQuickCreateStatusTarget) return

    const container = this.quickCreateStatusTarget
    container.replaceChildren()

    if (!message) return

    const paragraph = document.createElement("p")
    const classMap = {
      info: "text-muted",
      success: "text-success",
      error: "text-danger"
    }
    paragraph.className = classMap[state] || "text-muted"
    paragraph.textContent = message
    container.appendChild(paragraph)
  }

  renderGenerationStatus(message, state = "info") {
    if (!this.hasGenerationStatusTarget) return
    this.renderStatusMessage(this.generationStatusTarget, message, state)
  }

  renderLotPanelStatus(message, state = "info") {
    if (!this.hasLotPanelStatusTarget) return
    this.renderStatusMessage(this.lotPanelStatusTarget, message, state)
  }

  renderStatusMessage(container, message, state = "info") {
    container.replaceChildren()
    if (!message) return

    const paragraph = document.createElement("p")
    const classMap = {
      info: "text-muted",
      success: "text-success",
      error: "text-danger"
    }

    paragraph.className = classMap[state] || "text-muted"
    paragraph.textContent = message
    container.appendChild(paragraph)
  }

  switchCoreTab(event) {
    event.preventDefault()
    const tabId = event.currentTarget.dataset.coreTab
    if (!tabId) return
    this.showCoreTab(tabId)
  }

  showCoreTab(tabId) {
    this.coreTabTargets.forEach((tab) => {
      tab.classList.toggle("is-active", tab.dataset.coreTab === tabId)
    })
    this.coreTabPanelTargets.forEach((panel) => {
      panel.classList.toggle("d-none", panel.dataset.coreTab !== tabId)
    })

    if (tabId === "sublots" && this.currentLotId()) {
      this.fetchLotManagement()
    }
  }

  toggleGenerationPanel() {
    let lotId = this.currentLotId()
    if (!lotId) {
      lotId = this.selectFirstLotIfAvailable()
      if (lotId) {
        this.lotChanged()
      }
    }

    if (!lotId) {
      this.renderQuickStatus("Select a lot before generating core locations.", "error")
      return
    }

    this.showCoreTab("generate")
  }

  async generateCoreLocations() {
    let lotId = this.currentLotId()
    if (!lotId) {
      lotId = this.selectFirstLotIfAvailable()
      if (lotId) {
        this.lotChanged()
      }
    }

    if (!lotId) {
      this.renderGenerationStatus("Select a lot before generating.", "error")
      return
    }

    const payload = {
      core_generation: {
        seed: this.hasGenerationSeedTarget ? this.generationSeedTarget.value.trim() : "",
        mat_cores_per_sublot: this.hasGenerationMatCoresTarget ? this.generationMatCoresTarget.value : "1",
        joint_cores_per_joint: this.hasGenerationJointCoresTarget ? this.generationJointCoresTarget.value : "1",
        rounding_increment_ft: this.hasGenerationRoundingTarget ? this.generationRoundingTarget.value : "0.5",
        mat_edge_buffer_ft: this.hasGenerationMatBufferTarget ? this.generationMatBufferTarget.value : "1",
        lane_start_buffer_ft: this.hasGenerationLaneBufferTarget ? this.generationLaneBufferTarget.value : "10"
      }
    }

    this.setGenerationButtonState(true)
    this.renderGenerationStatus("Generating core locations...", "info")

    try {
      const data = await this.requestJson(
        `/projects/${this.projectIdValue}/asphalt_lots/${lotId}/core_generations`,
        { method: "POST", body: payload }
      )

      const generation = data.generation
      await this.fetchGenerations(lotId)
      if (generation?.id) {
        this.selectGeneration(generation.id)
        this.generationChanged()
      }

      this.renderGenerationStatus(data.message || "Core locations generated.", "success")
      this.renderQuickStatus("Core locations generated and linked to this report.", "success")
      this.showCoreTab("overview")
    } catch (error) {
      this.renderGenerationStatus(error.message || "Unable to generate core locations.", "error")
    } finally {
      this.setGenerationButtonState(false)
    }
  }

  selectGeneration(generationId) {
    const generationValue = String(generationId)
    this.currentGeneration = this.availableGenerations.find((gen) => String(gen.id) === generationValue) || null
    this.generationChanged()
  }

  toggleLotPanel() {
    let lotId = this.currentLotId()
    if (!lotId) {
      lotId = this.selectFirstLotIfAvailable()
      if (lotId) {
        this.lotChanged()
      }
    }

    if (!lotId) {
      this.renderQuickStatus("Select a lot before opening lot management.", "error")
      return
    }

    this.showCoreTab("sublots")
    this.fetchLotManagement()
  }

  closeInlinePanels() {
    if (this.hasCoreTabTarget) {
      this.showCoreTab("overview")
    }
  }

  async fetchLotManagement() {
    const lotId = this.currentLotId()
    if (!lotId || !this.hasLotPanelContentTarget) return

    this.renderLotPanelStatus("Loading lot details...", "info")

    try {
      const data = await this.requestJson(`/projects/${this.projectIdValue}/asphalt_lots/${lotId}/management_json`)
      this.renderLotPanel(data.lot)
      this.renderLotPanelStatus("", "info")
    } catch (error) {
      this.renderLotPanelStatus(error.message || "Unable to load lot details.", "error")
    }
  }

  renderLotPanel(lot) {
    if (!this.hasLotPanelContentTarget) return

    // Update "Manage in Project" link
    if (this.hasManageLotLinkTarget) {
      this.manageLotLinkTarget.href = `/projects/${this.projectIdValue}/asphalt_lots/${lot.id}`
      this.manageLotLinkTarget.style.display = ""
    }

    const lotDefaults = this.normalizedGenerationDefaults(lot.id)

    const sublotCards = (lot.sublots || []).length > 0
      ? lot.sublots.map((sublot) => this.sublotMarkup(sublot)).join("")
      : '<p class="text-muted">No sublots have been added yet.</p>'

    this.lotPanelContentTarget.innerHTML = `
      <div data-lot-root data-lot-id="${lot.id}">
        <h6 class="mb-2">Add Sublot</h6>
        <div class="form-row mb-3">
          <div class="form-group">
            <label class="text-muted-sm">Sublot Name (optional)</label>
            <input type="text" class="form-control" data-new-sublot-name placeholder="Auto name if blank">
          </div>
          <div class="form-group">
            <label class="text-muted-sm">Starter Lanes</label>
            <input type="number" min="0" value="0" class="form-control" data-new-sublot-lanes>
          </div>
          <div class="form-group">
            <label class="text-muted-sm">Lane Length (ft)</label>
            <input type="number" step="0.1" min="1" value="500" class="form-control" data-new-sublot-length>
          </div>
        </div>

        <div class="form-row mb-3">
          <div class="form-group">
            <label class="text-muted-sm">Lane Width (ft)</label>
            <input type="number" step="0.1" min="1" value="12" class="form-control" data-new-sublot-width>
          </div>
          <div class="form-group">
            <label class="text-muted-sm">Mat Cores per Sublot</label>
            <input type="number" min="1" value="${this.escapeHtml(String(lotDefaults.mat_cores_per_sublot))}" class="form-control" data-sublot-default="mat_cores_per_sublot">
          </div>
          <div class="form-group">
            <label class="text-muted-sm">Joint Cores per Sublot</label>
            <input type="number" min="0" value="${this.escapeHtml(String(lotDefaults.joint_cores_per_joint))}" class="form-control" data-sublot-default="joint_cores_per_joint">
          </div>
        </div>

        <div class="d-flex align-center gap-2 mb-3">
          <button type="button" class="btn btn-secondary btn-sm" data-inline-action="add-sublot">Add Sublot</button>
        </div>

        ${sublotCards}
      </div>
    `
  }

  sublotMarkup(sublot) {
    const laneRows = (sublot.lanes || []).map((lane) => this.laneRowMarkup(sublot, lane)).join("")
    const laneCount = (sublot.lanes || []).length
    const totalFt = (sublot.lanes || []).reduce((sum, l) => sum + (l.length_ft || 0), 0).toFixed(1)
    const lockMode = sublot.core_lock_mode || "none"
    const lockState = this.lockModeToToggleState(lockMode)

    const lockBadgeMap = {
      none: "",
      mat_only: '<span class="status-badge status-review">Mat Locked</span>',
      joint_only: '<span class="status-badge status-review">Joint Locked</span>',
      all: '<span class="status-badge status-revise">All Locked</span>'
    }

    return `
      <details class="nested-entry-card card-accent--blue mb-3" data-sublot-card-id="${sublot.id}" data-current-lock-mode="${lockMode}" open>
        <summary class="d-flex justify-between align-center mb-2" style="cursor:pointer; list-style:none;">
          <h6 class="mb-0">
            <span style="display:inline-block;width:1em;font-size:0.75em;color:var(--text-muted);">&#9660;</span>
            Sublot ${sublot.position}
            <span class="text-muted" style="font-size:0.85em;font-weight:normal;">
              &mdash; ${laneCount} lane${laneCount === 1 ? "" : "s"}, ${totalFt} ft
            </span>
          </h6>
          <div class="d-flex align-center gap-2">
            ${lockBadgeMap[lockMode] || ""}
          </div>
        </summary>

        <div class="d-flex align-center gap-3 mb-2">
          <label class="text-muted-sm mb-0">Lock Mode</label>
          ${["mat", "joint"].map(lockType => `
            <button type="button"
                    class="lock-toggle ${lockState[lockType] ? "is-locked" : ""}"
                    data-inline-action="toggle-lock-type"
                    data-sublot-id="${sublot.id}"
                    data-lock-type="${lockType}"
                    aria-pressed="${lockState[lockType] ? "true" : "false"}"
                    title="${lockState[lockType] ? "Locked" : "Unlocked"} — click to toggle">
              <span class="lock-toggle__label">${lockType === "mat" ? "Mat" : "Joint"}</span>
              <span class="lock-toggle__icon" aria-hidden="true">${this.lockIconSvg(lockState[lockType])}</span>
            </button>
          `).join("")}
        </div>

        <div class="d-flex align-center gap-2 mb-3">
          <button type="button" class="btn btn-outline-primary btn-sm" data-inline-action="generate-sublot" data-sublot-id="${sublot.id}">Generate Cores</button>
          <button type="button" class="btn btn-danger btn-sm" data-inline-action="delete-sublot" data-sublot-id="${sublot.id}">Delete</button>
        </div>

        <table class="modern-table table-compact mb-2" data-lane-table-id="${sublot.id}">
          <thead>
            <tr>
              <th>Lane</th>
              <th>Length (ft)</th>
              <th>Width (ft)</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody data-lane-table-body-id="${sublot.id}">
            ${laneRows.length > 0 ? laneRows : '<tr data-empty-lanes-row><td colspan="4" class="text-muted">No lanes defined for this sublot.</td></tr>'}
          </tbody>
        </table>

        <div class="d-flex align-center gap-2">
          <button type="button" class="btn btn-secondary btn-sm" data-inline-action="add-lane" data-sublot-id="${sublot.id}">Add Lane</button>
        </div>
      </details>
    `
  }

  laneRowMarkup(sublot, lane) {
    return `
      <tr data-lane-row-id="${lane.id}" data-lane-position="${lane.position}">
        <td class="font-bold">Lane ${lane.position}</td>
        <td>
          <input type="number" class="form-control form-control-sm" step="0.1" min="0.1" data-lane-field="length_ft" value="${this.escapeHtml(String(lane.length_ft ?? ""))}">
        </td>
        <td>
          <input type="number" class="form-control form-control-sm" step="0.1" min="0.1" data-lane-field="width_ft" value="${this.escapeHtml(String(lane.width_ft ?? ""))}">
        </td>
        <td>
          <button type="button" class="btn btn-sm btn-primary" data-inline-action="save-lane" data-sublot-id="${sublot.id}" data-lane-id="${lane.id}">Save</button>
          <button type="button" class="btn btn-sm btn-danger" data-inline-action="delete-lane" data-sublot-id="${sublot.id}" data-lane-id="${lane.id}">Delete</button>
        </td>
      </tr>
    `
  }

  draftLaneRowMarkup(sublotId, draftId, lanePosition) {
    return `
      <tr data-lane-draft-row-id="${draftId}" data-lane-position="${lanePosition}">
        <td class="font-bold">Lane ${lanePosition}</td>
        <td>
          <input type="number" class="form-control form-control-sm" step="0.1" min="0.1" data-lane-field="length_ft" value="">
        </td>
        <td>
          <input type="number" class="form-control form-control-sm" step="0.1" min="0.1" data-lane-field="width_ft" value="">
        </td>
        <td>
          <button type="button" class="btn btn-sm btn-primary" data-inline-action="create-lane" data-sublot-id="${sublotId}" data-draft-id="${draftId}">Save</button>
          <button type="button" class="btn btn-sm btn-danger" data-inline-action="discard-draft-lane" data-sublot-id="${sublotId}" data-draft-id="${draftId}">Delete</button>
        </td>
      </tr>
    `
  }

  lockIconSvg(isLocked) {
    const shackle = isLocked
      ? '<path d="M7 11V7a5 5 0 0 1 10 0v4"></path>'
      : '<path d="M7 11V7a5 5 0 0 1 9.9-1"></path>'
    return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"></rect>${shackle}</svg>`
  }

  lockModeToToggleState(lockMode) {
    switch (lockMode) {
      case "mat_only":
        return { mat: true, joint: false }
      case "joint_only":
        return { mat: false, joint: true }
      case "all":
        return { mat: true, joint: true }
      default:
        return { mat: false, joint: false }
    }
  }

  toggleStateToLockMode(lockState) {
    if (lockState.mat && lockState.joint) return "all"
    if (lockState.mat) return "mat_only"
    if (lockState.joint) return "joint_only"
    return "none"
  }

  generationDefaultsForLot(lotId) {
    const key = String(lotId)
    const defaults = this.lotGenerationDefaultsByLot[key] || {
      mat_cores_per_sublot: "1",
      joint_cores_per_joint: "1"
    }

    this.lotGenerationDefaultsByLot[key] = defaults
    return defaults
  }

  normalizedGenerationDefaults(lotId) {
    const defaults = this.generationDefaultsForLot(lotId)
    const mat = Number.parseInt(defaults.mat_cores_per_sublot, 10)
    const joint = Number.parseInt(defaults.joint_cores_per_joint, 10)

    return {
      mat_cores_per_sublot: Number.isInteger(mat) && mat > 0 ? String(mat) : "1",
      joint_cores_per_joint: Number.isInteger(joint) && joint >= 0 ? String(joint) : "1"
    }
  }

  isPositiveNumber(value) {
    const numberValue = Number(value)
    return Number.isFinite(numberValue) && numberValue > 0
  }

  optionsMarkupFromTarget(selectElement, selectedValue) {
    if (!selectElement) return ""

    return Array.from(selectElement.options).map((option) => {
      const selected = String(option.value) === String(selectedValue || "") ? " selected" : ""
      return `<option value="${this.escapeHtml(option.value)}"${selected}>${this.escapeHtml(option.textContent || "")}</option>`
    }).join("")
  }

  async handleLotPanelClick(event) {
    const actionButton = event.target.closest("[data-inline-action]")
    if (!actionButton) return

    const action = actionButton.dataset.inlineAction
    if (!action) return

    switch (action) {
      case "save-lot":
        await this.saveLot(actionButton)
        break
      case "delete-lot":
        await this.deleteLot(actionButton)
        break
      case "add-sublot":
        await this.addSublot(actionButton)
        break
      case "save-sublot":
        await this.saveSublot(actionButton)
        break
      case "delete-sublot":
        await this.deleteSublot(actionButton)
        break
      case "toggle-lock":
        await this.toggleSublotLock(actionButton)
        break
      case "toggle-lock-type":
        await this.toggleSublotLockType(actionButton)
        break
      case "set-lock-mode":
        await this.setSublotLockMode(actionButton)
        break
      case "add-lane":
        await this.addLane(actionButton)
        break
      case "create-lane":
        await this.createLaneFromDraft(actionButton)
        break
      case "discard-draft-lane":
        this.discardDraftLane(actionButton)
        break
      case "save-lane":
        await this.saveLane(actionButton)
        break
      case "delete-lane":
        await this.deleteLane(actionButton)
        break
      case "generate-sublot":
        await this.generateForSublot(actionButton)
        break
      default:
        break
    }
  }

  handleLotPanelInput(event) {
    const field = event.target.closest("[data-sublot-default]")
    if (!field) return

    const lotId = this.currentLotId()
    if (!lotId) return

    const defaults = this.generationDefaultsForLot(lotId)
    defaults[field.dataset.sublotDefault] = field.value
    this.lotGenerationDefaultsByLot[String(lotId)] = defaults
  }

  async saveLot(button) {
    const lotId = this.currentLotId()
    if (!lotId) return

    const root = this.lotPanelContentTarget.querySelector("[data-lot-root]")
    if (!root) return

    const payload = {
      asphalt_lot: {
        lot_number: this.valueFrom(root, '[data-lot-field="lot_number"]'),
        plant: this.valueFrom(root, '[data-lot-field="plant"]'),
        mix_type: this.valueFrom(root, '[data-lot-field="mix_type"]'),
        contractor: this.valueFrom(root, '[data-lot-field="contractor"]'),
        mix_design: this.valueFrom(root, '[data-lot-field="mix_design"]'),
        pg: this.valueFrom(root, '[data-lot-field="pg"]'),
        paving_date: this.valueFrom(root, '[data-lot-field="paving_date"]'),
        description: this.valueFrom(root, '[data-lot-field="description"]')
      }
    }

    await this.withButtonLoading(button, "Saving...", async () => {
      const data = await this.requestJson(`/projects/${this.projectIdValue}/asphalt_lots/${lotId}`, {
        method: "PATCH",
        body: payload
      })

      this.addLotOption(data.lot)
      this.renderLotPanelStatus("Lot details saved.", "success")
      this.renderQuickStatus(`Lot ${data.lot.lot_number} updated.`, "success")
      await this.fetchLotManagement()
    })
  }

  async deleteLot(button) {
    const lotId = this.currentLotId()
    if (!lotId) return
    if (!window.confirm("Delete this lot and all its sublots, lanes, and core generations?")) return

    await this.withButtonLoading(button, "Deleting...", async () => {
      await this.requestJson(`/projects/${this.projectIdValue}/asphalt_lots/${lotId}`, {
        method: "DELETE",
        expectNoContent: true
      })

      this.removeLotOption(lotId)
      this.renderLotPanelStatus("Lot deleted.", "success")
      this.renderQuickStatus("Lot deleted.", "success")

      if (this.hasLotSelectTarget && this.hasSelectableLots()) {
        const firstLotOption = Array.from(this.lotSelectTarget.options).find((option) => option.value)
        if (firstLotOption) {
          this.lotSelectTarget.value = firstLotOption.value
          this.lotChanged()
        }
      } else {
        this.lotSelectTarget.value = ""
        this.clearGenerations()
      }

      this.updateVisibility()
    })
  }

  async addSublot(button) {
    const lotId = this.currentLotId()
    if (!lotId) return

    const root = this.lotPanelContentTarget.querySelector("[data-lot-root]")
    if (!root) return

    const name = this.valueFrom(root, "[data-new-sublot-name]")
    const laneCount = Number(this.valueFrom(root, "[data-new-sublot-lanes]") || "0")
    const laneLength = this.valueFrom(root, "[data-new-sublot-length]") || "500"
    const laneWidth = this.valueFrom(root, "[data-new-sublot-width]") || "12"

    await this.withButtonLoading(button, "Adding...", async () => {
      const sublotData = await this.requestJson(
        `/projects/${this.projectIdValue}/asphalt_lots/${lotId}/asphalt_sublots`,
        {
          method: "POST",
          body: { asphalt_sublot: { name } }
        }
      )

      const sublotId = sublotData?.sublot?.id

      if (sublotId && laneCount > 0) {
        for (let i = 0; i < laneCount; i += 1) {
          await this.requestJson(
            `/projects/${this.projectIdValue}/asphalt_lots/${lotId}/asphalt_sublots/${sublotId}/asphalt_lanes`,
            {
              method: "POST",
              body: {
                asphalt_lane: {
                  length_ft: laneLength,
                  width_ft: laneWidth
                }
              }
            }
          )
        }
      }

      this.renderLotPanelStatus("Sublot added.", "success")
      await this.fetchLotManagement()
      this.refreshSelectedLotOptionFromManagement()
    })
  }

  async saveSublot(button) {
    const lotId = this.currentLotId()
    const sublotId = button.dataset.sublotId
    if (!lotId || !sublotId) return

    const sublotCard = this.lotPanelContentTarget.querySelector(`[data-sublot-card-id="${sublotId}"]`)
    if (!sublotCard) return

    const name = this.valueFrom(sublotCard, '[data-sublot-field="name"]')

    await this.withButtonLoading(button, "Saving...", async () => {
      await this.requestJson(
        `/projects/${this.projectIdValue}/asphalt_lots/${lotId}/asphalt_sublots/${sublotId}`,
        {
          method: "PATCH",
          body: { asphalt_sublot: { name } }
        }
      )

      this.renderLotPanelStatus("Sublot updated.", "success")
      await this.fetchLotManagement()
    })
  }

  async deleteSublot(button) {
    const lotId = this.currentLotId()
    const sublotId = button.dataset.sublotId
    if (!lotId || !sublotId) return
    if (!window.confirm("Delete this sublot and its lanes?")) return

    await this.withButtonLoading(button, "Deleting...", async () => {
      await this.requestJson(
        `/projects/${this.projectIdValue}/asphalt_lots/${lotId}/asphalt_sublots/${sublotId}`,
        {
          method: "DELETE",
          expectNoContent: true
        }
      )

      this.renderLotPanelStatus("Sublot deleted.", "success")
      await this.fetchLotManagement()
      this.refreshSelectedLotOptionFromManagement()
    })
  }

  async toggleSublotLock(button) {
    const lotId = this.currentLotId()
    const sublotId = button.dataset.sublotId
    if (!lotId || !sublotId) return

    await this.withButtonLoading(button, "Updating...", async () => {
      await this.requestJson(
        `/projects/${this.projectIdValue}/asphalt_lots/${lotId}/asphalt_sublots/${sublotId}/toggle_core_lock`,
        {
          method: "PATCH"
        }
      )

      this.renderLotPanelStatus("Sublot lock state updated.", "success")
      await this.fetchLotManagement()
    })
  }

  async setSublotLockMode(button) {
    const lotId = this.currentLotId()
    const sublotId = button.dataset.sublotId
    const lockMode = button.dataset.lockMode
    if (!lotId || !sublotId || !lockMode) return

    await this.withButtonLoading(button, "...", async () => {
      await this.requestJson(
        `/projects/${this.projectIdValue}/asphalt_lots/${lotId}/asphalt_sublots/${sublotId}/toggle_core_lock`,
        {
          method: "PATCH",
          body: { core_lock_mode: lockMode }
        }
      )

      this.renderLotPanelStatus(`Lock mode set to "${lockMode}" for sublot.`, "success")
      await this.fetchLotManagement()
    })
  }

  async toggleSublotLockType(button) {
    const lotId = this.currentLotId()
    const sublotId = button.dataset.sublotId
    const lockType = button.dataset.lockType
    if (!lotId || !sublotId || !lockType) return

    const sublotCard = this.lotPanelContentTarget.querySelector(`[data-sublot-card-id="${sublotId}"]`)
    if (!sublotCard) return

    const currentLockMode = sublotCard.dataset.currentLockMode || "none"
    const lockState = this.lockModeToToggleState(currentLockMode)
    if (!(lockType in lockState)) return

    lockState[lockType] = !lockState[lockType]
    const newLockMode = this.toggleStateToLockMode(lockState)

    await this.withButtonLoading(button, "...", async () => {
      await this.requestJson(
        `/projects/${this.projectIdValue}/asphalt_lots/${lotId}/asphalt_sublots/${sublotId}/toggle_core_lock`,
        {
          method: "PATCH",
          body: { core_lock_mode: newLockMode }
        }
      )

      this.renderLotPanelStatus(`Lock mode set to "${newLockMode}" for sublot.`, "success")
      await this.fetchLotManagement()
    })
  }

  async addLane(button) {
    const sublotId = button.dataset.sublotId
    if (!sublotId) return

    const tbody = this.lotPanelContentTarget.querySelector(`[data-lane-table-body-id="${sublotId}"]`)
    if (!tbody) return

    const draftId = `draft-${sublotId}-${this.laneDraftCounter++}`

    const existingPositions = Array.from(tbody.querySelectorAll("[data-lane-position]"))
      .map((row) => Number(row.dataset.lanePosition || 0))
      .filter((position) => Number.isFinite(position))

    const nextPosition = (existingPositions.length > 0 ? Math.max(...existingPositions) : 0) + 1

    const emptyRow = tbody.querySelector("[data-empty-lanes-row]")
    if (emptyRow) emptyRow.remove()

    tbody.insertAdjacentHTML("beforeend", this.draftLaneRowMarkup(sublotId, draftId, nextPosition))
    this.renderLotPanelStatus("New lane row added. Enter length and width, then save.", "info")
  }

  async createLaneFromDraft(button) {
    const lotId = this.currentLotId()
    const sublotId = button.dataset.sublotId
    const draftId = button.dataset.draftId
    if (!lotId || !sublotId || !draftId) return

    const row = this.lotPanelContentTarget.querySelector(`[data-lane-draft-row-id="${draftId}"]`)
    if (!row) return

    const lengthFt = this.valueFrom(row, '[data-lane-field="length_ft"]').trim()
    const widthFt = this.valueFrom(row, '[data-lane-field="width_ft"]').trim()

    if (!this.isPositiveNumber(lengthFt) || !this.isPositiveNumber(widthFt)) {
      this.renderLotPanelStatus("Enter positive values for lane length and width before saving.", "error")
      return
    }

    await this.withButtonLoading(button, "Saving...", async () => {
      await this.requestJson(
        `/projects/${this.projectIdValue}/asphalt_lots/${lotId}/asphalt_sublots/${sublotId}/asphalt_lanes`,
        {
          method: "POST",
          body: {
            asphalt_lane: {
              length_ft: lengthFt,
              width_ft: widthFt
            }
          }
        }
      )

      this.renderLotPanelStatus("Lane added.", "success")
      await this.fetchLotManagement()
    })
  }

  discardDraftLane(button) {
    const draftId = button.dataset.draftId
    const sublotId = button.dataset.sublotId
    if (!draftId || !sublotId) return

    const row = this.lotPanelContentTarget.querySelector(`[data-lane-draft-row-id="${draftId}"]`)
    if (!row) return

    const tbody = row.closest("tbody")
    row.remove()

    if (!tbody) return
    const remainingRows = tbody.querySelectorAll("tr")
    if (remainingRows.length === 0) {
      tbody.insertAdjacentHTML("beforeend", '<tr data-empty-lanes-row><td colspan="4" class="text-muted">No lanes defined for this sublot.</td></tr>')
    }
  }

  async saveLane(button) {
    const lotId = this.currentLotId()
    const sublotId = button.dataset.sublotId
    const laneId = button.dataset.laneId
    if (!lotId || !sublotId || !laneId) return

    const row = this.lotPanelContentTarget.querySelector(`[data-lane-row-id="${laneId}"]`)
    if (!row) return

    const lengthFt = this.valueFrom(row, '[data-lane-field="length_ft"]')
    const widthFt = this.valueFrom(row, '[data-lane-field="width_ft"]')

    await this.withButtonLoading(button, "Saving...", async () => {
      await this.requestJson(
        `/projects/${this.projectIdValue}/asphalt_lots/${lotId}/asphalt_sublots/${sublotId}/asphalt_lanes/${laneId}`,
        {
          method: "PATCH",
          body: {
            asphalt_lane: {
              length_ft: lengthFt,
              width_ft: widthFt
            }
          }
        }
      )

      this.renderLotPanelStatus("Lane updated.", "success")
      await this.fetchLotManagement()
    })
  }

  async deleteLane(button) {
    const lotId = this.currentLotId()
    const sublotId = button.dataset.sublotId
    const laneId = button.dataset.laneId
    if (!lotId || !sublotId || !laneId) return
    if (!window.confirm("Delete this lane?")) return

    await this.withButtonLoading(button, "Deleting...", async () => {
      await this.requestJson(
        `/projects/${this.projectIdValue}/asphalt_lots/${lotId}/asphalt_sublots/${sublotId}/asphalt_lanes/${laneId}`,
        {
          method: "DELETE",
          expectNoContent: true
        }
      )

      this.renderLotPanelStatus("Lane deleted.", "success")
      await this.fetchLotManagement()
    })
  }

  async generateForSublot(button) {
    const lotId = this.currentLotId()
    const sublotId = button.dataset.sublotId
    if (!lotId || !sublotId) return

    const defaults = this.normalizedGenerationDefaults(lotId)

    await this.withButtonLoading(button, "Generating...", async () => {
      const data = await this.requestJson(
        `/projects/${this.projectIdValue}/asphalt_lots/${lotId}/core_generations/create_for_sublot?sublot_id=${encodeURIComponent(sublotId)}`,
        {
          method: "POST",
          body: {
            core_generation: {
              mat_cores_per_sublot: defaults.mat_cores_per_sublot,
              joint_cores_per_joint: defaults.joint_cores_per_joint
            }
          }
        }
      )

      await this.fetchGenerations(lotId)
      if (data.generation?.id) {
        this.selectGeneration(data.generation.id)
        this.generationChanged()
      }

      this.renderLotPanelStatus(data.message || "Core generation created for sublot.", "success")
      this.renderQuickStatus("Core locations generated and linked to this report.", "success")
    })
  }

  async refreshSelectedLotOptionFromManagement() {
    const lotId = this.currentLotId()
    if (!lotId) return

    try {
      const data = await this.requestJson(`/projects/${this.projectIdValue}/asphalt_lots/${lotId}/management_json`)
      const lot = data?.lot
      if (!lot) return

      this.addLotOption({
        id: lot.id,
        lot_number: lot.lot_number,
        mix_type: lot.mix_type,
        sublots_count: lot.sublots?.length || 0
      })
    } catch (_error) {
      // Option text refresh is non-blocking.
    }
  }

  valueFrom(root, selector) {
    const element = root.querySelector(selector)
    return element ? element.value : ""
  }

  async withButtonLoading(button, loadingLabel, callback) {
    const defaultLabel = button.textContent
    button.disabled = true
    button.textContent = loadingLabel

    try {
      await callback()
    } catch (error) {
      this.renderLotPanelStatus(error.message || "Request failed.", "error")
    } finally {
      button.disabled = false
      button.textContent = defaultLabel
    }
  }

  currentLotId() {
    if (!this.hasLotSelectTarget) return ""
    return this.lotSelectTarget.value
  }

  selectFirstLotIfAvailable() {
    if (!this.hasLotSelectTarget || this.currentLotId()) return this.currentLotId()

    const firstLotOption = Array.from(this.lotSelectTarget.options).find((option) => option.value && !option.disabled)
    if (!firstLotOption) return ""

    this.lotSelectTarget.value = firstLotOption.value
    return firstLotOption.value
  }

  selectedLotOptionText() {
    if (!this.hasLotSelectTarget) return ""
    const option = this.lotSelectTarget.selectedOptions[0]
    return option ? option.textContent.trim() : ""
  }

  ensureSelectedLotStatusMessage() {
    if (!this.hasQuickCreateStatusTarget || !this.hasSelectableLots()) return
    if (this.quickCreateStatusTarget.textContent.trim()) return

    const label = this.selectedLotOptionText()
    if (label) {
      this.renderQuickStatus(`${label} selected. Generate core locations next.`, "info")
    }
  }

  async requestJson(url, options = {}) {
    const method = options.method || "GET"
    const headers = {
      "Accept": "application/json"
    }

    if (method !== "GET") {
      headers["X-CSRF-Token"] = this.csrfToken()
    }

    const fetchOptions = {
      method,
      headers
    }

    if (options.body !== undefined) {
      headers["Content-Type"] = "application/json"
      fetchOptions.body = JSON.stringify(options.body)
    }

    const response = await fetch(url, fetchOptions)

    if (options.expectNoContent && response.status === 204) {
      return {}
    }

    const text = await response.text()
    let data = {}
    if (text) {
      try {
        data = JSON.parse(text)
      } catch (_error) {
        data = {}
      }
    }

    if (!response.ok) {
      const errors = Array.isArray(data.errors) ? data.errors.join(" ") : null
      throw new Error(errors || data.error || "Request failed.")
    }

    return data
  }

  escapeHtml(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
      .replace(/'/g, "&#39;")
  }

  csrfToken() {
    const token = document.querySelector('meta[name="csrf-token"]')
    return token ? token.content : ""
  }
}
