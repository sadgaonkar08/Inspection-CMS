import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    email: String,
    threshold: { type: Number, default: 5 },
    windowMs: { type: Number, default: 1500 }
  }

  connect() {
    this.clickTimes = []
  }

  async trigger(event) {
    event.preventDefault()
    const now = Date.now()
    this.clickTimes = this.clickTimes.filter(t => now - t < this.windowMsValue)
    this.clickTimes.push(now)

    if (this.clickTimes.length < this.thresholdValue) return
    this.clickTimes = []

    const ok = window.confirm(`Generate a new API token for ${this.emailValue}?\n\nThis will replace any existing token.`)
    if (!ok) return

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": csrf
        }
      })

      if (!response.ok) {
        window.alert(`Failed to generate token (HTTP ${response.status}).`)
        return
      }

      const data = await response.json()
      window.prompt("Your new API token (copy it now — it won't be shown again):", data.token)
    } catch (err) {
      window.alert(`Error generating token: ${err.message}`)
    }
  }
}
