import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

// Inline the subscribeToExport function to avoid nested import issues
function subscribeToExport(exportId, callbacks) {
  return consumer.subscriptions.create(
    { channel: "ReportExportChannel", export_id: exportId },
    {
      connected() {
        console.log(`Connected to export ${exportId}`)
        if (callbacks.connected) callbacks.connected()
      },
      disconnected() {
        console.log(`Disconnected from export ${exportId}`)
        if (callbacks.disconnected) callbacks.disconnected()
      },
      received(data) {
        console.log("Received data:", data)
        if (callbacks.received) callbacks.received(data)
      }
    }
  )
}

// Connects to data-controller="report-export"
export default class extends Controller {
  static targets = ["button", "progress", "progressBar", "progressText", "message", "download"]
  static values = { reportId: Number }

  connect() {
    console.log("ReportExport controller connected for report:", this.reportIdValue)
    console.log("Button target:", this.buttonTarget)
  }

  startExport(event) {
    console.log("startExport called!")
    event.preventDefault()

    // Hide button, show progress
    this.buttonTarget.classList.add("d-none")
    this.progressTarget.classList.remove("d-none")
    
    // Start the export
    fetch(`/reports/${this.reportIdValue}/start_export`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    .then(response => response.json())
    .then(data => {
      console.log("Export started:", data)
      this.subscribeToProgress(data.export_id)
    })
    .catch(error => {
      console.error("Error starting export:", error)
      this.showError("Failed to start export. Please try again.")
    })
  }

  subscribeToProgress(exportId) {
    this.subscription = subscribeToExport(exportId, {
      received: (data) => {
        console.log("Progress update:", data)
        
        if (data.status === 'failed') {
          this.showError(data.error || "Export failed", {
            flags: data.error_flags || [],
            stage: data.error_stage || null
          })
        } else if (data.status === 'completed') {
          this.showComplete(exportId)
        } else {
          this.updateProgress(data.progress, data.message)
        }
      }
    })
  }

  updateProgress(percent, message) {
    this.progressBarTarget.style.width = `${percent}%`
    this.progressBarTarget.setAttribute('aria-valuenow', percent)
    this.progressTextTarget.textContent = `${percent}%`
    
    if (message) {
      this.messageTarget.textContent = message
    }
  }

  showComplete(exportId) {
    this.updateProgress(100, "Export completed!")
    
    // Show download button
    setTimeout(() => {
      this.progressTarget.classList.add("d-none")
      this.downloadTarget.classList.remove("d-none")
      
      // Set the download URL
      const downloadLink = this.downloadTarget.querySelector('a')
      if (downloadLink) {
        downloadLink.href = `/reports/${this.reportIdValue}/report_exports/${exportId}/download`
      }
    }, 500)
    
    // Unsubscribe from channel
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
  }

  showError(errorMessage, options = {}) {
    const flags = Array.isArray(options.flags) ? options.flags : []
    const stage = options.stage

    this.progressTarget.classList.remove("d-none")
    this.progressBarTarget.style.width = "0%"
    this.progressBarTarget.classList.remove("progress-bar-animated")

    const prettyFlags = flags.map((flag) => this.prettyFlag(flag)).join(", ")
    const stagePrefix = stage ? `[${stage}] ` : ""
    const flagSuffix = prettyFlags ? ` (${prettyFlags})` : ""

    this.messageTarget.textContent = `Error: ${stagePrefix}${errorMessage}${flagSuffix}`
    this.messageTarget.classList.remove("text-muted")
    this.messageTarget.classList.add("text-danger")
    this.buttonTarget.classList.remove("d-none")
    this.buttonTarget.textContent = "Retry Export"
    this.downloadTarget.classList.add("d-none")
    
    // Unsubscribe from channel
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
  }

  disconnect() {
    // Clean up subscription when controller disconnects
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
  }

  prettyFlag(flag) {
    const labels = {
      template_missing: "Template Missing",
      python_runtime_error: "Python Runtime Error",
      image_processing_error: "Image Processing Error",
      data_serialization_error: "Data Serialization Error",
      filesystem_error: "Filesystem Error",
      timeout_or_resource_error: "Timeout/Resource Error",
      unknown_failure: "Unknown Failure"
    }

    return labels[flag] || String(flag)
  }
}
