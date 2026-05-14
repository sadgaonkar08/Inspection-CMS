import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "details", "icon"]

  connect() {
    this.syncState()
  }

  toggle() {
    if (!this.hasDetailsTarget) return

    this.detailsTarget.classList.toggle("d-none")
    this.syncState()
  }

  syncState() {
    const expanded = this.hasDetailsTarget && !this.detailsTarget.classList.contains("d-none")

    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute("aria-expanded", expanded ? "true" : "false")
    }

    if (this.hasIconTarget) {
      this.iconTarget.textContent = expanded ? "-" : "+"
    }
  }
}