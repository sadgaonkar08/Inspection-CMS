import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

// Connects to data-controller="lab-test-import"
// Subscribes to LabTestImportChannel and reloads the status panel when status changes.
export default class extends Controller {
  static targets = ["statusBadge", "statusPanel", "rowCount", "labName", "elapsed", "stallWarning"]
  static values = {
    id: Number,
    initialStatus: String,
    startedAt: Number,
    stallThreshold: { type: Number, default: 30000 }
  }

  connect() {
    if (this.isTerminal(this.initialStatusValue)) {
      return
    }

    this.subscription = consumer.subscriptions.create(
      { channel: "LabTestImportChannel", import_id: this.idValue },
      {
        received: (data) => this.onStatusChange(data)
      }
    )

    this.startElapsedTimer()
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    this.stopElapsedTimer()
  }

  startElapsedTimer() {
    if (!this.hasElapsedTarget || !this.startedAtValue) return
    this.tick()
    this.elapsedTimer = setInterval(() => this.tick(), 1000)
  }

  stopElapsedTimer() {
    if (this.elapsedTimer) {
      clearInterval(this.elapsedTimer)
      this.elapsedTimer = null
    }
  }

  tick() {
    const elapsedMs = Date.now() - this.startedAtValue
    if (this.hasElapsedTarget) {
      this.elapsedTarget.textContent = this.formatElapsed(elapsedMs)
    }
    if (this.hasStallWarningTarget && elapsedMs >= this.stallThresholdValue) {
      this.stallWarningTarget.classList.remove("d-none")
    }
  }

  formatElapsed(ms) {
    const totalSeconds = Math.max(0, Math.floor(ms / 1000))
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60
    return `${minutes}:${seconds.toString().padStart(2, "0")}`
  }

  onStatusChange(data) {
    if (this.hasStatusBadgeTarget) {
      this.statusBadgeTarget.textContent = this.humanize(data.status)
      this.statusBadgeTarget.className = `badge badge-${this.badgeClass(data.status)}`
    }
    if (this.hasRowCountTarget && data.row_count != null) {
      this.rowCountTarget.textContent = data.row_count
    }
    if (this.hasLabNameTarget && data.lab_name) {
      this.labNameTarget.textContent = data.lab_name
    }

    if (this.isTerminal(data.status)) {
      this.stopElapsedTimer()
      // Reload to render the server-side status panel for the new state.
      window.location.reload()
    }
  }

  isTerminal(status) {
    return ["saved", "needs_review", "rejected"].includes(status)
  }

  humanize(s) {
    if (!s) return ""
    return s.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase())
  }

  badgeClass(status) {
    switch (status) {
      case "saved": return "success"
      case "needs_review": return "warning"
      case "rejected": return "danger"
      case "pending": return "info"
      default: return "secondary"
    }
  }
}
