import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="lab-test-import-form"
// Shows the lot dropdown only for asphalt specs (P-401/P-403) and the report
// dropdown only for concrete specs (P-610). The sets of spec codes are passed
// via data-*-value so the logic stays in sync with LabTestImport constants.
export default class extends Controller {
  static targets = ["specCode", "lotField", "reportField"]
  static values = {
    asphaltSpecs: Array,
    concreteSpecs: Array
  }

  connect() {
    this.refresh()
  }

  specChanged() {
    this.refresh()
  }

  refresh() {
    const spec = this.specCodeTarget.value
    this.toggle(this.lotFieldTarget, this.asphaltSpecsValue.includes(spec))
    this.toggle(this.reportFieldTarget, this.concreteSpecsValue.includes(spec))
  }

  toggle(el, visible) {
    if (!el) return
    el.classList.toggle("d-none", !visible)
    // When hiding, clear the selected value so we don't submit a stale id.
    if (!visible) {
      const select = el.querySelector("select")
      if (select) select.value = ""
    }
  }
}
