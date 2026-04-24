import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

// Connects to data-controller="lab-test-import"
// Subscribes to LabTestImportChannel and reloads the status panel when status changes.
export default class extends Controller {
  static targets = ["statusBadge", "statusPanel", "rowCount", "labName"]
  static values = {
    id: Number,
    initialStatus: String
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
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
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
