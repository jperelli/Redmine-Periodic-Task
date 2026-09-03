class Periodictask < ActiveRecord::Base
  include Redmine::I18n
  extend Redmine::I18n

  belongs_to :project
  belongs_to :author, class_name: 'User', foreign_key: 'author_id', optional: true
  belongs_to :assigned_to, class_name: 'Principal', foreign_key: 'assigned_to_id'
  belongs_to :tracker, optional: true
  belongs_to :issue_category, class_name: 'IssueCategory', foreign_key: 'issue_category_id'
  has_many :periodictask_issues, dependent: :delete_all
  has_many :issues, through: :periodictask_issues
  attribute :custom_field_values, :json
  attribute :watcher_user_ids, :json, default: []
  attribute :subtasks, :json, default: []
  attribute :relations, :json, default: []

  SUBTASK_KEYS = %w[tracker_id subject assigned_to_id estimated_hours].freeze
  RELATION_KEYS = %w[relation_type issue_id delay].freeze

  # Subtask templates: array of hashes with SUBTASK_KEYS, each becoming a child
  # issue of the generated issue. Accepts an array or an index-keyed hash as
  # posted by the form; blank rows are dropped.
  def subtasks
    Array(super).map { |s| s.to_h.stringify_keys.slice(*SUBTASK_KEYS) }
  end

  def subtasks=(value)
    rows = self.class.normalize_rows(value, SUBTASK_KEYS)
    rows.each do |row|
      row['estimated_hours'] = row['estimated_hours'].to_hours if row['estimated_hours'].is_a?(String)
    end
    super(rows.reject { |row| row.values.all?(&:blank?) })
  end

  # Related issue templates: array of hashes with RELATION_KEYS, each becoming
  # an IssueRelation from the generated issue to an existing issue.
  def relations
    Array(super).map { |r| r.to_h.stringify_keys.slice(*RELATION_KEYS) }
  end

  def relations=(value)
    rows = self.class.normalize_rows(value, RELATION_KEYS)
    super(rows.reject { |row| row['issue_id'].blank? && row['delay'].blank? })
  end

  def self.normalize_rows(value, keys)
    value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
    value = value.values if value.is_a?(Hash)
    Array(value).filter_map do |row|
      row = row.to_unsafe_h if row.respond_to?(:to_unsafe_h)
      next unless row.respond_to?(:to_h)

      row = row.to_h.stringify_keys.slice(*keys)
      row.transform_values! { |v| v.is_a?(String) ? v.strip.presence : v }
      row
    end
  end

  def watcher_user_ids
    Array(super).map(&:to_i).reject(&:zero?)
  end

  def watcher_user_ids=(value)
    super(Array(value).map(&:to_i).reject(&:zero?))
  end

  # Tags are stored as a comma-separated string (the format the RedmineUP Tags
  # plugin itself uses for `Issue#tag_list=`). Accepts a string or an array.
  def tag_list=(value)
    write_attribute :tag_list, self.class.normalize_tag_names(value).join(', ').presence
  end

  def tag_names
    self.class.normalize_tag_names(tag_list)
  end

  def self.normalize_tag_names(value)
    Array(value).flat_map { |v| v.to_s.split(',') }.map(&:strip).reject(&:blank?).uniq
  end

  # True when a tagging plugin (RedmineUP Tags or the older redmine_tags) has
  # patched Issue with acts_as_taggable, whichever plugin id it registers under.
  def self.tags_plugin_installed?
    Issue.method_defined?(:tag_list=) && Issue.respond_to?(:available_tags)
  end

  # Tracker the generated issues will use: the configured one or the project's first.
  def effective_tracker
    tracker || project&.trackers&.first
  end

  # % Done is only usable when Redmine takes it from the issue field (not from
  # the status) and the tracker has it enabled in its core fields.
  def done_ratio_enabled?
    Issue.use_field_for_done_ratio? && effective_tracker.present? &&
      effective_tracker.core_fields.include?('done_ratio')
  end

  # Accept "h:mm" / "1h30" / decimal input like Redmine's issue estimated time.
  def estimated_hours=(hours)
    write_attribute :estimated_hours, (hours.is_a?(String) ? (hours.to_hours || hours) : hours)
  end

  after_initialize do |task|
    if task.new_record?
      task.interval_number ||= 1
      task.interval_units ||= INTERVAL_UNITS.first
    end
  end

  validates :interval_number, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :interval_units, presence: true
  validates :done_ratio, inclusion: { in: 0..100 }, allow_nil: true
  validate :validate_subtasks_and_relations

  scope :accessible, lambda {
    if User.current.allowed_to?(:periodictask, nil, global: true)
      all
    else
      where('1 = 0')
    end
  }

  INTERVAL_UNITS = %w[day business_day week month year].freeze

  # Localized [label, value] pairs for select inputs.
  # Built per call so labels reflect the current user's locale instead of
  # being frozen to the boot-time default locale.
  def self.interval_units_options
    [
      [l(:label_unit_day), 'day'],
      [l(:label_unit_business_day), 'business_day'],
      [l(:label_unit_week), 'week'],
      [l(:label_unit_month), 'month'],
      [l(:label_unit_year), 'year']
    ]
  end

  def generate_issue(now = Time.current)
    return unless project.try(:active?)

    # Copy subject and description and replace variables
    subj = parse_macro(subject.try(:dup), now)
    desc = parse_macro(description.try(:dup), now)

    issue = Issue.new(project_id: project_id,
                      tracker_id: effective_tracker.try(:id),
                      category_id: issue_category_id, parent_id: parent_id,
                      assigned_to_id: assigned_to_id, author_id: author_id,
                      subject: subj, description: desc)
    issue.priority_id = priority_id if priority_id.present?
    issue.status_id = status_id if status_id.present?
    issue.done_ratio = done_ratio if done_ratio.present? && done_ratio_enabled?
    issue.start_date ||= now.to_date if set_start_date?
    if due_date_number
      due_date_units ||= 'day'
      units = due_date_units.downcase
      # Count the offset from the issue's start date when it was set, otherwise from now.
      base = set_start_date? && issue.start_date ? issue.start_date.to_time : now
      issue.due_date = if units == 'business_day'
                         due_date_number.business_day.after(base)
                       else
                         due_date_number.send(units).since(base)
                       end
    end
    issue.estimated_hours = estimated_hours

    fill_checklists issue
    fill_tags issue
    fill_custom_fields issue

    issue
  end

  # Records that +issue+ was generated by this periodic task, so it shows up
  # in the run history on the detail page. Ignored if already recorded.
  def record_generated_issue(issue)
    return unless issue&.persisted?

    periodictask_issues.create(issue_id: issue.id) unless periodictask_issues.exists?(issue_id: issue.id)
  end

  # Everything that needs the generated issue to be persisted first: watchers,
  # subtasks, relations and the run history. Returns the error messages of the
  # subtasks/relations that could not be created (the issue itself is kept).
  def complete_generated_issue(issue, now = Time.current)
    fill_watchers(issue)
    record_generated_issue(issue)
    create_subtasks(issue, now) + create_relations(issue)
  end

  # Creates a child issue per subtask template under +issue+. Returns error messages.
  def create_subtasks(issue, now = Time.current)
    return [] unless issue.persisted?

    subtasks.each_with_object([]) do |template, errors|
      child = Issue.new(project_id: issue.project_id,
                        tracker_id: template['tracker_id'].presence || issue.tracker_id,
                        author_id: issue.author_id,
                        assigned_to_id: template['assigned_to_id'].presence || issue.assigned_to_id,
                        subject: parse_macro(template['subject'].to_s.dup, now),
                        estimated_hours: template['estimated_hours'].presence)
      child.parent_issue_id = issue.id
      if child.save
        record_generated_issue(child)
      else
        errors << "#{l(:label_subtask_plural)} \"#{template['subject']}\": #{child.errors.full_messages.join(', ')}"
      end
    end
  end

  # Creates an IssueRelation from +issue+ to each configured issue. Returns error messages.
  def create_relations(issue)
    return [] unless issue.persisted?

    relations.each_with_object([]) do |template, errors|
      relation = IssueRelation.new
      relation.issue_from = issue
      relation.issue_to = Issue.visible.find_by(id: template['issue_id'])
      relation.relation_type = template['relation_type']
      relation.delay = template['delay'].presence
      relation.init_journals(User.current)
      unless relation.save
        errors << "#{l(:label_related_issues)} ##{template['issue_id']}: #{relation.errors.full_messages.join(', ')}"
      end
    end
  end

  # Issues previously generated by this task that still exist, newest first.
  # The join with the issues table transparently excludes deleted issues.
  def created_issues
    issues.reorder(created_on: :desc)
  end

  def fill_watchers(issue)
    return if watcher_user_ids.blank?
    return unless issue.persisted?

    watcher_user_ids.each do |uid|
      uid = uid.to_i
      next if uid.zero?

      user = User.find_by(id: uid)
      issue.add_watcher(user) if user
    end
  end

  # Records a create/update/delete in the activity log. Called from the
  # controller (not a model callback) so the scheduler's own writes to
  # next_run_date / last_error are not logged as user edits.
  def log_activity(action, user = User.current)
    PeriodictaskJournal.create(
      periodictask_id: id,
      project_id: project_id,
      user_id: user&.id,
      action: action,
      subject: subject,
      created_on: Time.current
    )
  end

  def get_next_run_date(now = Time.current)
    units = interval_units.downcase
    val = next_run_date || now
    if units == 'business_day'
      val = interval_number.business_day.after(val) while val <= now
    else
      interval_steps = ((now - val) / interval_number.send(units)).ceil
      val += (interval_number * interval_steps).send(units)
    end
    val
  end

  private

  def validate_subtasks_and_relations
    subtasks.each do |row|
      errors.add(:base, l(:error_subtask_subject_blank)) if row['subject'].blank?
    end
    relations.each do |row|
      errors.add(:base, l(:error_relation_type_invalid)) unless IssueRelation::TYPES.key?(row['relation_type'].to_s)
      errors.add(:base, l(:error_relation_issue_invalid)) unless row['issue_id'].to_s =~ /\A\d+\z/
    end
  end

  def parse_macro(str, now)
    if str.respond_to?(:gsub!) && str.present?
      previous_month_time = now - 1.month
      str.gsub!('**DAY**', now.strftime('%d'))
      str.gsub!('**WEEKISO**', now.strftime('%V'))
      str.gsub!('**WEEK**', now.strftime('%W'))
      str.gsub!('**QUARTER**', (((now.month - 1) / 3) + 1).to_s)
      str.gsub!('**MONTHNAME**', I18n.localize(now, format: '%B'))
      str.gsub!('**MONTH**', now.strftime('%m'))
      str.gsub!('**YEAR**', now.strftime('%Y'))
      str.gsub!('**PREVIOUS_MONTHNAME**', I18n.localize(previous_month_time, format: '%B'))
      str.gsub!('**PREVIOUS_MONTH**', previous_month_time.strftime('%m'))
    end
    str
  end

  def fill_checklists(issue)
    if checklists_template_id && Redmine::Plugin.all.any? do |p|
      p.id == :redmine_checklists
    end && Object.const_defined?('ChecklistTemplate')
      template = ChecklistTemplate.find(checklists_template_id)
      if template
        items = template.template_items.split("\n")
        checklists = items.each_with_index.map do |x, i|
          {
            is_done: false,
            subject: x,
            position: i
          }
        end
        issue.checklists_attributes = checklists
      end
    end
  end

  # The tagging plugin persists tags from an after_save callback on Issue, so
  # assigning the list before the issue is saved is all that is needed.
  def fill_tags(issue)
    return unless self.class.tags_plugin_installed?

    names = tag_names
    issue.tag_list = names if names.any?
  end

  def fill_custom_fields(issue)
    values = if custom_field_values.respond_to?(:to_unsafe_hash)
               custom_field_values.to_unsafe_hash
             elsif custom_field_values.respond_to?(:to_hash)
               custom_field_values.to_hash
             end

    return if values.nil?

    issue.custom_field_values = values.stringify_keys
  end
end
