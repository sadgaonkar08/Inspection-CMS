import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // These targets must match the data-spec-drilldown-target attributes in your HTML
  static targets = ["modal", "viewDivisions", "viewSpecs", "viewForm", "specListContainer", "modalTitle", "checklistFormPlaceholder"]
  
  // Captures the Report ID (if it exists)
  static values = { reportId: String }

  connect() {
    this.allSpecs = [];
    this.currentSpec = null;
    this.loadSpecs();
    this.broadcastChecklistChange();
  }

  disconnect() {
    if (this.hasModalTarget && this.modalTarget.open) {
      this.modalTarget.close();
    }
    this.clearChecklistForm();
    this.allSpecs = [];
    this.currentSpec = null;
  }

  async loadSpecs() {
    try {
      const response = await fetch("/spec_items.json");
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      this.allSpecs = await response.json();
      console.log("Maestro: Specs loaded successfully", this.allSpecs.length);
      this.renderDivisionButtons();
    } catch (e) {
      console.error("Maestro Error: Could not load spec items", e);
      this.allSpecs = [];
    }
  }

  renderDivisionButtons() {
    const container = this.viewDivisionsTarget;
    const divisions = [...new Set(this.allSpecs.map(s => s.division))].sort();
    container.innerHTML = divisions.map(div => `
      <button type="button"
              class="spec-selection-btn"
              data-action="click->spec-drilldown#selectDivision"
              data-division="${div}">
        <strong>${div}</strong>
        <span>›</span>
      </button>
    `).join("");
  }

  // Normalize lookup so ids match even if serialized as strings
  findSpecById(id) {
    const numericId = Number(id);
    return this.allSpecs.find((spec) => Number(spec.id) === numericId);
  }

  // --- MODAL ACTIONS ---

  openModal() {
    console.log("Maestro: Opening Spec Modal");
    // Show the dialog
    this.modalTarget.showModal();
    // Reset to the first view (Divisions)
    this.showDivisions();
  }

  closeModal() {
    this.modalTarget.close();
    this.clearChecklistForm();
  }

  // --- VIEW SWITCHING ---

  showDivisions() {
    this.viewDivisionsTarget.classList.remove('d-none');
    this.viewSpecsTarget.classList.add('d-none');
    this.viewFormTarget.classList.add('d-none');
    this.modalTitleTarget.innerText = "Select Division";
  }
  
  showSpecs() {
    this.viewDivisionsTarget.classList.add('d-none');
    this.viewSpecsTarget.classList.remove('d-none');
    this.viewFormTarget.classList.add('d-none');
  }

  // --- SELECTION LOGIC ---

  selectDivision(event) {
    // 1. Get the division name from the clicked button
    const divisionName = event.currentTarget.dataset.division;
    
    // 2. Filter specs
    const specs = this.allSpecs.filter(s => s.division === divisionName);
    
    // 3. Render the list of specs
    let html = "";
    specs.forEach(spec => {
      html += `
        <button type="button" class="spec-selection-btn" 
                data-action="click->spec-drilldown#selectSpec" 
                data-id="${spec.id}">
          <strong class="text-primary">${spec.code}</strong>
          <span class="text-muted-sm">${spec.description}</span>
        </button>
      `;
    });
    this.specListContainerTarget.innerHTML = html;
    
    // 4. Switch View
    this.modalTitleTarget.innerText = divisionName;
    this.showSpecs();
  }

  selectSpec(event) {
    const specId = parseInt(event.currentTarget.dataset.id);
    this.currentSpec = this.findSpecById(specId);
    
    // Check if spec has checklist questions
    const questions = this.normalizeQuestions(this.currentSpec.checklist_questions || []);
    
    if (questions.length === 0) {
      alert('This specification does not have any checklist questions defined.');
      return;
    }
    
    // Pass empty object {} because this is a new checklist
    this.renderChecklistForm(questions, {});
    
    this.viewSpecsTarget.classList.add('d-none');
    this.viewFormTarget.classList.remove('d-none');
    this.modalTitleTarget.innerText = `Checklist: ${this.currentSpec.code}`;
  }

  async deleteSpec(event) {
    const card = event.target.closest(".gallery-card")
    if (!card) return

    const specCode = card.dataset.specCode || "this checklist"
    if (!window.confirm(`Delete ${specCode}? Any answers for this checklist will be lost.`)) return

    const entryId = card.dataset.entryId

    if (this.reportIdValue && entryId) {
      try {
        const response = await fetch(`/reports/${this.reportIdValue}/checklist_entries/${entryId}`, {
          method: "DELETE",
          headers: {
            "Accept": "application/json",
            "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
          }
        })
        if (!response.ok) {
          alert(`Could not delete checklist (HTTP ${response.status}).`)
          return
        }
      } catch (e) {
        alert("Network error while deleting checklist.")
        return
      }
    }

    card.remove()

    const list = document.getElementById("active-checklists-list")
    if (list && !list.querySelector(".gallery-card")) {
      list.innerHTML = `
        <div class="spec-empty-state">
          <div class="spec-empty-icon">📋</div>
          <div class="spec-empty-title">No spec checklists added yet</div>
          <div class="spec-empty-subtitle">Add required inspection checklists for this report. You can edit them anytime.</div>
          <button type="button"
                  class="btn btn-primary"
                  data-action="click->spec-drilldown#openModal">
            + Add Spec Checklist
          </button>
        </div>
      `
    }

    this.broadcastChecklistChange()
  }

  editSpec(event) {
    // Handle editing an existing card
    const card = event.target.closest(".gallery-card");
    const specId = parseInt(card.dataset.specId);
    const savedAnswers = JSON.parse(card.dataset.answers || "{}");
    
    this.currentSpec = this.findSpecById(specId);
    
    const questions = this.normalizeQuestions(this.currentSpec.checklist_questions || []);
    
    if (questions.length === 0) {
      alert('This specification does not have any checklist questions defined.');
      return;
    }
    
    this.modalTarget.showModal();
    this.renderChecklistForm(questions, savedAnswers);
    
    this.viewDivisionsTarget.classList.add('d-none');
    this.viewSpecsTarget.classList.add('d-none');
    this.viewFormTarget.classList.remove('d-none');
    this.modalTitleTarget.innerText = `Edit: ${this.currentSpec.code}`;
  }

  // --- QUESTION NORMALIZATION ---
  // Handles both legacy string arrays and new object arrays
  normalizeQuestions(questions) {
    if (!Array.isArray(questions)) return [];
    
    return questions.map((q, idx) => {
      if (typeof q === 'string') {
        // Legacy format - convert to object
        return {
          id: this.generateQuestionId(q, idx),
          prompt: q,
          kind: 'radio',
          options: ['Yes', 'No', 'N/A'],
          required: false
        };
      }
      // Already an object - ensure defaults
      return {
        id: q.id || this.generateQuestionId(q.prompt, idx),
        prompt: q.prompt || q,
        kind: q.kind || 'radio',
        options: q.options || ['Yes', 'No', 'N/A'],
        placeholder: q.placeholder || '',
        help_text: q.help_text || '',
        required: q.required || false,
        default_value: q.default_value,
        validation: q.validation || {},
        followups: Array.isArray(q.followups) ? q.followups : []
      };
    });
  }

  generateQuestionId(prompt, index) {
    const base = prompt.toString().toLowerCase().replace(/[^a-z0-9\s]/g, '').replace(/\s+/g, '_');
    return `${base}_${index + 1}`;
  }

  // --- FORM RENDERING ---

  renderChecklistForm(questions, savedAnswers = {}) {
    if (!questions || questions.length === 0) {
      this.checklistFormPlaceholderTarget.innerHTML = '<p class="text-muted">No checklist questions available for this specification.</p>';
      return;
    }
    
    let html = `<div>`;
    html += `<p class="mb-4"><strong>${questions.length} items to check:</strong></p>`;
    
    questions.forEach((q) => {
      const questionId = q.id;
      const savedValue = savedAnswers[questionId] ?? savedAnswers[q.prompt] ?? q.default_value ?? '';
      const followups = this.followupsForQuestion(q);
      const requiredMark = q.required ? '<span class="text-danger">*</span>' : '';
      
      html += `<div class="checklist-item-row">`;
      html += `<p class="checklist-question">${q.prompt}${requiredMark}</p>`;
      
      if (q.help_text) {
        html += `<p class="checklist-help-text text-muted-sm">${q.help_text}</p>`;
      }
      
      html += `<div class="checklist-options">`;
      
      switch (q.kind) {
        case 'radio':
          html += this.renderRadioField(questionId, q.options || ['Yes', 'No', 'N/A'], savedValue, followups);
          break;
          
        case 'checkbox':
          html += this.renderCheckboxField(questionId, q.options || [], savedValue);
          break;
          
        case 'text':
          html += this.renderTextField(questionId, q.placeholder, savedValue, q.validation);
          break;
          
        case 'number':
          html += this.renderNumberField(questionId, q.placeholder, savedValue, q.validation);
          break;
          
        case 'textarea':
          html += this.renderTextareaField(questionId, q.placeholder, savedValue, q.validation);
          break;
          
        default:
          // Fallback to radio for unknown types
          html += this.renderRadioField(questionId, ['Yes', 'No', 'N/A'], savedValue, followups);
      }

      if (Array.isArray(followups) && followups.length) {
        html += this.renderFollowups(questionId, followups, savedAnswers, savedValue);
      }
      
      html += `</div></div>`;
    });

    html += `
      <div class="mt-4" style="display: flex; gap: 10px; justify-content: flex-end;">
        <button type="button" class="btn btn-secondary" data-action="click->spec-drilldown#saveAndAddAnother">Save & Add Another</button>
        <button type="button" class="btn btn-primary" data-action="click->spec-drilldown#saveAndClose">Save & Close</button>
      </div>
    `;
    html += `</div>`;
    
    this.checklistFormPlaceholderTarget.innerHTML = html;
  }

  renderRadioField(questionId, options, savedValue, followups = []) {
    const safeId = questionId.replace(/"/g, '&quot;');
    const shouldToggleFollowups = Array.isArray(followups) && followups.length > 0;
    return options.map(opt => {
      const checked = savedValue === opt ? 'checked' : '';
      const followupAttrs = shouldToggleFollowups
        ? `data-action="change->spec-drilldown#toggleFollowups" data-question-id="${this.escapeHtml(questionId)}"`
        : '';
      return `<label><input type="radio" name="answers[${safeId}]" value="${opt}" ${checked} ${followupAttrs}> ${opt}</label>`;
    }).join('\n');
  }

  renderCheckboxField(questionId, options, savedValue) {
    const safeId = questionId.replace(/"/g, '&quot;');
    const selectedValues = Array.isArray(savedValue) ? savedValue : (savedValue ? [savedValue] : []);
    
    return options.map(opt => {
      const checked = selectedValues.includes(opt) ? 'checked' : '';
      return `<label><input type="checkbox" name="answers[${safeId}][]" value="${opt}" ${checked}> ${opt}</label>`;
    }).join('\n');
  }

  renderTextField(questionId, placeholder, savedValue, validation = {}) {
    const safeId = questionId.replace(/"/g, '&quot;');
    const pattern = validation.pattern ? `pattern="${validation.pattern}"` : '';
    const maxLength = validation.max ? `maxlength="${validation.max}"` : '';
    
    return `<input type="text" 
                   name="answers[${safeId}]" 
                   value="${this.escapeHtml(savedValue)}" 
                   placeholder="${placeholder || ''}"
                   class="form-control checklist-text-input"
                   ${pattern} ${maxLength}>`;
  }

  renderNumberField(questionId, placeholder, savedValue, validation = {}) {
    const safeId = questionId.replace(/"/g, '&quot;');
    const min = validation.min !== undefined ? `min="${validation.min}"` : '';
    const max = validation.max !== undefined ? `max="${validation.max}"` : '';
    const step = validation.step ? `step="${validation.step}"` : 'step="any"';
    
    return `<input type="number" 
                   name="answers[${safeId}]" 
                   value="${savedValue}" 
                   placeholder="${placeholder || ''}"
                   class="form-control checklist-number-input"
                   ${min} ${max} ${step}>`;
  }

  renderTextareaField(questionId, placeholder, savedValue, validation = {}) {
    const safeId = questionId.replace(/"/g, '&quot;');
    const maxLength = validation.max ? `maxlength="${validation.max}"` : '';
    
    return `<textarea name="answers[${safeId}]" 
                      placeholder="${placeholder || ''}"
                      class="form-control checklist-textarea"
                      rows="3"
                      ${maxLength}>${this.escapeHtml(savedValue)}</textarea>`;
  }

  renderFollowups(questionId, followups, savedAnswers, selectedValue) {
    if (!Array.isArray(followups) || followups.length === 0) return '';
    const safeQuestionId = this.escapeHtml(questionId);
    return followups.map((followup) => {
      const triggerValue = followup.value || 'Yes';
      const followupKey = followup.key || this.buildFollowupKey(questionId, triggerValue);
      const savedValue = savedAnswers[followupKey] ?? '';
      const shouldShow = selectedValue === triggerValue;
      const hiddenClass = shouldShow ? '' : 'd-none';
      const disabledAttr = shouldShow ? '' : 'disabled';
      const label = followup.label || 'Details';
      const placeholder = followup.placeholder || 'Provide details...';
      const kind = followup.kind || 'textarea';
      const fieldMarkup = kind === 'text'
        ? `<input type="text" name="answers[${this.escapeHtml(followupKey)}]" value="${this.escapeHtml(savedValue)}" placeholder="${this.escapeHtml(placeholder)}" class="form-control checklist-text-input" ${disabledAttr}>`
        : `<textarea name="answers[${this.escapeHtml(followupKey)}]" placeholder="${this.escapeHtml(placeholder)}" class="form-control checklist-textarea" rows="3" ${disabledAttr}>${this.escapeHtml(savedValue)}</textarea>`;

      return `
        <div class="checklist-followup ${hiddenClass}" data-followup-question-id="${safeQuestionId}" data-followup-value="${this.escapeHtml(triggerValue)}">
          <label class="checklist-followup-label">${this.escapeHtml(label)}</label>
          ${fieldMarkup}
        </div>
      `;
    }).join('');
  }

  followupsForQuestion(question) {
    const explicitFollowups = Array.isArray(question.followups) ? [...question.followups] : [];

    if (!this.isP403Spec()) return explicitFollowups;
    if ((question.kind || 'radio') !== 'radio') return explicitFollowups;

    const options = Array.isArray(question.options) && question.options.length
      ? question.options
      : ['Yes', 'No', 'N/A'];
    const triggerValue = this.defaultP403FollowupTrigger(question);
    if (!options.includes(triggerValue)) return explicitFollowups;

    const hasTriggerFollowup = explicitFollowups.some((followup) =>
      String(followup?.value || '').toLowerCase() === triggerValue.toLowerCase()
    );

    if (!hasTriggerFollowup) {
      explicitFollowups.push({
        value: triggerValue,
        key: this.buildFollowupKey(question.id, triggerValue),
        label: 'Explain',
        placeholder: 'Describe what happened and any corrective action taken.',
        kind: 'textarea'
      });
    }

    return explicitFollowups;
  }

  isP403Spec() {
    const code = this.currentSpec?.code;
    if (!code) return false;
    return String(code).trim().toUpperCase() === 'P-403';
  }

  defaultP403FollowupTrigger(question) {
    const prompt = String(question?.prompt || '').toLowerCase();
    const isDeviationQuestion = prompt.includes('deviate from the approved paving plan');
    return isDeviationQuestion ? 'Yes' : 'No';
  }

  buildFollowupKey(questionId, value) {
    const slug = value
      .toString()
      .toLowerCase()
      .replace(/[^a-z0-9\s]/g, '')
      .trim()
      .replace(/\s+/g, '_') || 'detail';
    return `${questionId}__${slug}`;
  }

  toggleFollowups(event) {
    const questionId = event.target.dataset.questionId;
    if (!questionId || !this.hasChecklistFormPlaceholderTarget) return;
    const selectedValue = event.target.value;
    const escapedId = this.escapeSelector(questionId);
    const containers = this.checklistFormPlaceholderTarget.querySelectorAll(`[data-followup-question-id="${escapedId}"]`);

    containers.forEach((container) => {
      const triggerValue = container.dataset.followupValue;
      const shouldShow = triggerValue === selectedValue;
      container.classList.toggle('d-none', !shouldShow);
      container.querySelectorAll('input, textarea').forEach((input) => {
        input.disabled = !shouldShow;
        if (!shouldShow) input.value = '';
      });
    });
  }

  escapeSelector(value) {
    if (window.CSS && typeof window.CSS.escape === 'function') {
      return window.CSS.escape(value);
    }
    return value.replace(/[^a-zA-Z0-9_-]/g, '\\$&');
  }

  escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }
  
  // --- SAVING LOGIC ---

  saveAndClose(event) {
    this.saveChecklist(event, true);
  }

  saveAndAddAnother(event) {
    this.saveChecklist(event, false);
  }

  saveChecklist(event, closeAfter = true) {
    const btn = event.target;
    const originalText = btn.innerText;
    btn.disabled = true;
    btn.innerText = "Saving...";

    // 1. Harvest Answers from all input types
    const answers = {};
    const form = this.checklistFormPlaceholderTarget;
    
    // Collect radio button values
    const radios = form.querySelectorAll('input[type="radio"]:checked');
    radios.forEach(radio => {
      const keyMatch = radio.name.match(/answers\[(.*?)\]/);
      if (keyMatch) {
        answers[keyMatch[1]] = radio.value;
      }
    });

    // Collect checkbox values (as arrays)
    const checkboxGroups = {};
    const checkboxes = form.querySelectorAll('input[type="checkbox"]:checked');
    checkboxes.forEach(checkbox => {
      const keyMatch = checkbox.name.match(/answers\[(.*?)\]/);
      if (keyMatch) {
        const key = keyMatch[1].replace('[]', '');
        if (!checkboxGroups[key]) checkboxGroups[key] = [];
        checkboxGroups[key].push(checkbox.value);
      }
    });
    Object.assign(answers, checkboxGroups);

    // Collect text inputs
    const textInputs = form.querySelectorAll('input[type="text"][name^="answers"]');
    textInputs.forEach(input => {
      if (input.disabled) return;
      const keyMatch = input.name.match(/answers\[(.*?)\]/);
      if (keyMatch) {
        answers[keyMatch[1]] = input.value;
      }
    });

    // Collect number inputs
    const numberInputs = form.querySelectorAll('input[type="number"][name^="answers"]');
    numberInputs.forEach(input => {
      if (input.disabled) return;
      const keyMatch = input.name.match(/answers\[(.*?)\]/);
      if (keyMatch) {
        // Store as number if valid, otherwise as string
        const val = input.value;
        answers[keyMatch[1]] = val !== '' ? parseFloat(val) : '';
      }
    });

    // Collect textareas
    const textareas = form.querySelectorAll('textarea[name^="answers"]');
    textareas.forEach(textarea => {
      if (textarea.disabled) return;
      const keyMatch = textarea.name.match(/answers\[(.*?)\]/);
      if (keyMatch) {
        answers[keyMatch[1]] = textarea.value;
      }
    });

    // 2. CHECK: Are we in "Draft Mode" (New Report) or "Edit Mode" (Saved Report)?
    if (!this.reportIdValue) {
      // --- DRAFT MODE: Inject Hidden Fields ---
      // We generate a unique ID so Rails knows this is a new nested record
      const uniqueId = new Date().getTime();
      
      const mockData = {
        spec_code: this.currentSpec.code,
        spec_desc: this.currentSpec.description,
        id: null 
      };
      
      this.addBadgeToUI(mockData, answers, uniqueId);
      
      if (closeAfter) {
        this.closeModal();
      } else {
        // Reset to division selection for adding another
        this.clearChecklistForm();
        this.showDivisions();
      }
      
      btn.disabled = false;
      btn.innerText = originalText;

    } else {
      // --- SAVED MODE: Use AJAX ---
      fetch(`/reports/${this.reportIdValue}/checklist_entries`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({
          spec_item_id: this.currentSpec.id,
          answers: answers
        })
      })
      .then(response => response.json())
      .then(data => {
        if (data.status === "success") {
          this.addBadgeToUI(data, answers, null);
          
          if (closeAfter) {
            this.closeModal();
          } else {
            // Reset to division selection for adding another
            this.clearChecklistForm();
            this.showDivisions();
          }
        } else {
          alert("Error saving: " + data.message);
        }
      })
      .catch(error => {
        console.error(error);
        alert("Network Error");
      })
      .finally(() => {
        btn.disabled = false;
        btn.innerText = originalText;
      });
    }
  }

  addBadgeToUI(data, newAnswers, newRecordId = null) {
    const list = document.getElementById("active-checklists-list");
    
    // Remove "No checklists" message
    const emptyMsg = list.querySelector(".spec-empty-state");
    if (emptyMsg) emptyMsg.remove();

    // Check if card already exists (Update vs Create)
    let card = list.querySelector(`[data-spec-code="${data.spec_code}"]`);
    
    if (card) {
      // UPDATE EXISTING
      card.dataset.answers = JSON.stringify(newAnswers);
      // Visual flash
      card.classList.add('flash-success');
      setTimeout(() => card.classList.remove('flash-success'), 1000);
      
      // If it's a draft mode item, we should ideally update the hidden input too, 
      // but simpler to just let them delete and re-add for now in draft mode.
      if (newRecordId) {
         // Logic to update hidden field value would go here
         const hiddenInput = card.querySelector(`input[name*="[checklist_answers]"]`);
         if(hiddenInput) hiddenInput.value = JSON.stringify(newAnswers);
      }

    } else {
      // CREATE NEW
      let hiddenFields = "";
      
      // If NewRecordId is present, we are in Draft Mode -> Inject Hidden Inputs
      if (newRecordId) {
        // Emit spec_item_id
        hiddenFields = `<input type="hidden" name="report[checklist_entries_attributes][${newRecordId}][spec_item_id]" value="${this.currentSpec.id}">`;
        
        // Emit individual hidden inputs for each answer key
        Object.entries(newAnswers).forEach(([key, value]) => {
          const escapedKey = this.escapeHtml(key);
          
          if (Array.isArray(value)) {
            // Checkbox arrays - emit multiple inputs with []
            value.forEach(item => {
              hiddenFields += `<input type="hidden" name="report[checklist_entries_attributes][${newRecordId}][checklist_answers][${escapedKey}][]" value="${this.escapeHtml(item)}">`;
            });
          } else {
            // Single values (radio, text, number, textarea)
            hiddenFields += `<input type="hidden" name="report[checklist_entries_attributes][${newRecordId}][checklist_answers][${escapedKey}]" value="${this.escapeHtml(value)}">`;
          }
        });
      }

      const entryId = newRecordId ? "" : (data.id || "")
      const html = `
        <div class="gallery-card p-3 text-left"
             data-spec-code="${data.spec_code}"
             data-spec-id="${this.currentSpec?.id || ''}"
             data-entry-id="${entryId}"
             data-answers='${JSON.stringify(newAnswers)}'>

          ${hiddenFields}

          <div class="font-bold text-primary mb-2">${data.spec_code}</div>
          <div class="text-muted-sm mb-2 clamp-2">${data.spec_desc}</div>

          <div class="d-flex gap-2">
            <button type="button"
                    class="btn-secondary flex-1 text-muted-sm"
                    data-action="click->spec-drilldown#editSpec">
               ✎ Edit
            </button>
            <button type="button"
                    class="btn-danger text-muted-sm"
                    data-action="click->spec-drilldown#deleteSpec"
                    aria-label="Delete checklist">
               ✕
            </button>
          </div>
        </div>
      `;
      list.insertAdjacentHTML("beforeend", html);
    }

    this.broadcastChecklistChange();
  }

  broadcastChecklistChange() {
    const list = document.getElementById("active-checklists-list");
    if (!list) return;

    const codes = Array.from(list.querySelectorAll(".gallery-card[data-spec-code]"))
      .map((card) => (card.dataset.specCode || "").toUpperCase().trim())
      .filter((code) => code.length > 0);

    document.dispatchEvent(new CustomEvent("spec-checklists:changed", {
      detail: { codes }
    }));
  }

  clearChecklistForm() {
    if (this.hasChecklistFormPlaceholderTarget) {
      this.checklistFormPlaceholderTarget.innerHTML = "";
    }
  }
}