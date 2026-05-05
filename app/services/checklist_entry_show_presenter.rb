class ChecklistEntryShowPresenter
  DetailRow = Struct.new(:key, :label, :full_label, :answer, keyword_init: true)
  QuestionRow = Struct.new(:key, :label, :answer, :negative, :details, keyword_init: true) do
    def expandable?
      details.any?
    end
  end

  def initialize(entry)
    @entry = entry
  end

  def rows
    @rows ||= begin
      remaining_answers = normalized_answers.dup
      rendered_rows = []

      normalized_questions.each do |question|
        answer_key = question_answer_key(question, remaining_answers)
        detail_rows = extract_detail_rows(question, remaining_answers)
        next unless answer_key || detail_rows.any?

        answer = answer_key ? remaining_answers.delete(answer_key) : nil
        rendered_rows << QuestionRow.new(
          key: answer_key || question[:id].to_s,
          label: question_label(question),
          answer: format_answer(answer),
          negative: negative_answer?(answer),
          details: detail_rows
        )
      end

      remaining_answers.each do |key, answer|
        rendered_rows << QuestionRow.new(
          key: key,
          label: fallback_label_for(key),
          answer: format_answer(answer),
          negative: negative_answer?(answer),
          details: []
        )
      end

      rendered_rows
    end
  end

  private

  attr_reader :entry

  def normalized_answers
    entry.checklist_answers.to_h.transform_keys(&:to_s)
  end

  def normalized_questions
    Array(entry.spec_item&.normalized_questions)
  end

  def question_answer_key(question, answers)
    question_aliases(question).find { |candidate| answers.key?(candidate) }
  end

  def question_aliases(question)
    [question[:id].to_s, question[:prompt].to_s].select(&:present?).uniq
  end

  def question_label(question)
    question[:prompt].presence || humanize_key(question[:id])
  end

  def extract_detail_rows(question, answers)
    detail_rows = []

    explicit_followup_keys(question).each do |detail|
      next unless answers.key?(detail[:key])

      detail_rows << DetailRow.new(
        key: detail[:key],
        label: detail[:label],
        full_label: "#{question_label(question)} - #{detail[:label]}",
        answer: format_answer(answers.delete(detail[:key]))
      )
    end

    wildcard_prefix = "#{question[:id]}__"
    answers.keys.each do |key|
      next unless key.start_with?(wildcard_prefix)

      suffix = key.delete_prefix(wildcard_prefix)
      detail_rows << DetailRow.new(
        key: key,
        label: humanize_key(suffix),
        full_label: "#{question_label(question)} - #{humanize_key(key)}",
        answer: format_answer(answers.delete(key))
      )
    end

    detail_rows
  end

  def explicit_followup_keys(question)
    Array(question[:followups]).map do |followup|
      followup = followup.respond_to?(:with_indifferent_access) ? followup.with_indifferent_access : followup
      trigger_value = followup[:value].presence || "Yes"
      label = followup[:label].presence || "Details"
      followup_key = followup[:key].presence || build_followup_key(question[:id], trigger_value)

      { key: followup_key.to_s, label: label.to_s }
    end
  end

  def build_followup_key(question_id, value)
    slug = value
      .to_s
      .downcase
      .gsub(/[^a-z0-9\s]/, "")
      .strip
      .gsub(/\s+/, "_")
      .presence || "detail"

    "#{question_id}__#{slug}"
  end

  def fallback_label_for(key)
    explicit_followup = explicit_followup_lookup[key]
    return explicit_followup if explicit_followup.present?

    wildcard_followup = wildcard_followup_label_for(key)
    return wildcard_followup if wildcard_followup.present?

    humanize_key(key)
  end

  def explicit_followup_lookup
    @explicit_followup_lookup ||= normalized_questions.each_with_object({}) do |question, lookup|
      explicit_followup_keys(question).each do |detail|
        lookup[detail[:key]] = "#{question_label(question)} - #{detail[:label]}"
      end
    end
  end

  def wildcard_followup_label_for(key)
    parent_key, suffix = key.split("__", 2)
    return if suffix.blank?

    question = normalized_questions.find { |item| item[:id].to_s == parent_key }
    return unless question

    "#{question_label(question)} - #{humanize_key(suffix)}"
  end

  def format_answer(answer)
    return "" if answer.nil?
    return answer.join(", ") if answer.is_a?(Array)

    answer.to_s
  end

  def negative_answer?(answer)
    values = answer.is_a?(Array) ? answer : [answer]
    values.compact.map { |value| value.to_s.strip.downcase }.include?("no")
  end

  def humanize_key(value)
    value.to_s.tr("_", " ").tr("-", " ").squish.humanize
  end
end