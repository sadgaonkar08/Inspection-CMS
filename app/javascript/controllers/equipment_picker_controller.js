import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "modal", 
    "equipmentCheckbox", 
    "globalContractor", 
    "globalHours",
    "selectionCount",
    "summary",
    "createBtn"
  ]
  
  static values = {
    reportContractor: String
  }

  connect() {
    console.log("🛠️ Equipment Picker Controller Connected");
    this.successMessageTimeout = null;
    
    // Pre-fill contractor from report if available
    if (this.hasGlobalContractorTarget && this.reportContractorValue) {
      this.globalContractorTarget.value = this.reportContractorValue;
    }
  }

  disconnect() {
    if (this.successMessageTimeout) {
      clearTimeout(this.successMessageTimeout);
      this.successMessageTimeout = null;
    }

    if (this.hasModalTarget && this.modalTarget.open) {
      this.modalTarget.close();
    }
  }

  openModal() {
    this.modalTarget.showModal();
    this.updateSelection(); // Initialize button state
  }

  closeModal() {
    this.modalTarget.close();
    this.clearSelections();
  }

  updateSelection() {
    const selectedCount = this.equipmentCheckboxTargets.filter(cb => cb.checked).length;
    
    // Update summary
    if (this.hasSelectionCountTarget) {
      this.selectionCountTarget.textContent = selectedCount;
    }
    
    // Enable/disable create button
    if (this.hasCreateBtnTarget) {
      this.createBtnTarget.disabled = selectedCount === 0;
    }
  }

  createEntries() {
    const selected = this.equipmentCheckboxTargets.filter(cb => cb.checked);
    
    if (selected.length === 0) {
      alert("Please select at least one piece of equipment.");
      return;
    }

    // Get global values
    const globalContractor = this.hasGlobalContractorTarget ? this.globalContractorTarget.value : "";
    const globalHours = this.hasGlobalHoursTarget ? this.globalHoursTarget.value : "";

    // Get the equipment template and container
    const template = document.getElementById("equipment-template");
    const container = document.getElementById("equipment-fields-container");

    if (!template || !container) {
      console.error("Equipment template or container not found");
      return;
    }

    // Create one entry for each selected equipment
    selected.forEach(checkbox => {
      const equipmentName = checkbox.dataset.equipmentName;
      
      // Clone the template
      const content = template.content.cloneNode(true);
      const uniqueId = `${Date.now()}${Math.floor(Math.random() * 100000)}`;

      // Update all inputs with unique IDs
      content.querySelectorAll("input, select, textarea").forEach((el) => {
        if (el.name) {
          el.name = el.name.replace("NEW_RECORD", uniqueId);
        }
        if (el.id) {
          el.id = el.id.replace("NEW_RECORD", uniqueId);
        }
      });

      // Pre-fill values
      const makeModelField = content.querySelector('[name*="[make_model]"]');
      const contractorField = content.querySelector('[name*="[contractor]"]');
      const hoursField = content.querySelector('[name*="[hours]"]');
      const quantityField = content.querySelector('[name*="[quantity]"]');

      if (makeModelField) {
        // If it's a select, try to set the value; otherwise set as text input
        if (makeModelField.tagName === 'SELECT') {
          makeModelField.value = equipmentName;
        } else if (makeModelField.tagName === 'INPUT') {
          makeModelField.value = equipmentName;
        }
      }

      if (contractorField && globalContractor) {
        contractorField.value = globalContractor;
      }

      if (hoursField && globalHours) {
        hoursField.value = globalHours;
      }

      if (quantityField) {
        quantityField.value = "1";
      }

      // Append to container
      container.appendChild(content);
    });

    // Close modal and clear selections
    this.closeModal();
    
    // Show success feedback
    this.showSuccessMessage(selected.length);
  }

  clearSelections() {
    // Uncheck all checkboxes
    this.equipmentCheckboxTargets.forEach(cb => {
      cb.checked = false;
    });
    
    // Clear global fields (but keep contractor if it was from report)
    if (this.hasGlobalHoursTarget) {
      this.globalHoursTarget.value = "";
    }
    
    // Reset contractor to report default
    if (this.hasGlobalContractorTarget && this.reportContractorValue) {
      this.globalContractorTarget.value = this.reportContractorValue;
    }
    
    this.updateSelection();
  }

  showSuccessMessage(count) {
    const summary = this.summaryTarget;
    const originalText = summary.innerHTML;
    
    summary.innerHTML = `✓ Created ${count} equipment ${count === 1 ? 'entry' : 'entries'}`;
    summary.style.color = "var(--success)";
    
    this.successMessageTimeout = setTimeout(() => {
      summary.innerHTML = originalText;
      summary.style.color = "";
    }, 3000);
  }
}
