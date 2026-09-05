class Periodictask < ActiveRecord::Base
  include Redmine::I18n
  extend Redmine::I18n

  belongs_to :project
  belongs_to :author, class_name: 'User', foreign_key: 'author_id', optional: true
  belongs_to :assigned_to, class_name: 'Principal', foreign_key: 'assigned_to_id'
  belongs_to :tracker, optional: true
  belongs_to :issue_category, class_name: 'IssueCategory', foreign_key: 'issue_category_id'
  belongs_to :fixed_version, class_name: 'Version', foreign_key: 'fixed_version_id', optional: true
  has_many :periodictask_issues, dependent: :delete_all
  has_many :issues, through: :periodictask_issues
  attribute :custom_field_values, :json
  attribute :watcher_user_ids, :json, default: []
  attribute :subtasks, :json, default: []
  attribute :relations, :json, default: []
  attribute :weekdays, :json, default: []
  attribute :month_weeks, :json, default: []

  SUBTASK_KEYS = %w[tracker_id subject assigned_to_id estimated_hours].freeze
  RELATION_KEYS = %w[relation_type issue_id delay].freeze

  # Identity, ownership and the outcome of past runs belong to the source task;
  # everything else describes the template and is worth copying.
  COPY_EXCLUDED_ATTRIBUTES = %w[id project_id author_id created_at updated_at last_error].freeze

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

  # Weekdays (0 = Sunday .. 6 = Saturday, as Time#wday) the task recurs on when
  # the interval unit is 'week', or monthly in 'weekday' mode. Empty means the
  # plain "every N weeks" behaviour.
  def weekdays
    self.class.normalize_selection(super, WEEKDAYS)
  end

  def weekdays=(value)
    super(self.class.normalize_selection(value, WEEKDAYS))
  end

  # Ordinal occurrences (1 = first .. 5 = fifth) of the selected weekdays within
  # each month, for monthly 'weekday' mode. A fifth occurrence that does not
  # exist in a month resolves to the last one.
  def month_weeks
    self.class.normalize_selection(super, MONTH_WEEKS)
  end

  def month_weeks=(value)
    super(self.class.normalize_selection(value, MONTH_WEEKS))
  end

  # 'day_of_month' (same calendar day as the anchor, the historical behaviour)
  # or 'weekday' (selected ordinals x selected weekdays).
  def monthly_mode
    value = super
    MONTHLY_MODES.include?(value) ? value : MONTHLY_MODES.first
  end

  def monthly_weekday_mode?
    interval_units == 'month' && monthly_mode == 'weekday'
  end

  def self.normalize_selection(value, allowed)
    Array(value).filter_map { |v| Integer(v.to_s, 10, exception: false) }.select { |v| allowed.include?(v) }.uniq.sort
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

  # True when the redmine_checklists plugin is registered and its template
  # model is loaded, so checklists can be copied onto generated issues.
  def self.checklists_plugin_installed?
    Redmine::Plugin.all.any? { |p| p.id == :redmine_checklists } && Object.const_defined?('ChecklistTemplate')
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
  validate :validate_recurrence
  before_validation :clear_irrelevant_recurrence_options

  # Tasks the scheduler picks up. A disabled task keeps its schedule and can
  # still be run by hand from the list or detail page.
  scope :active, -> { where(is_active: true) }

  scope :accessible, lambda {
    if User.current.allowed_to?(:periodictask, nil, global: true)
      all
    else
      where('1 = 0')
    end
  }

  INTERVAL_UNITS = %w[day business_day week month year].freeze
  WEEKDAYS = (0..6).to_a.freeze
  MONTH_WEEKS = (1..5).to_a.freeze
  MONTHLY_MODES = %w[day_of_month weekday].freeze

  # Date macros, optionally suffixed with a day offset: **DAY-1** renders the
  # component of the date N days before the run, **MONTH+10** N days after it.
  # Offsets shift the whole date, so **DAY-1**/**MONTH-1**/**YEAR-1** yields
  # yesterday even across a month or year boundary.
  DATE_MACRO = /\*\*(DAY|WEEKISO|WEEK|QUARTER|MONTHNAME|MONTH|YEAR)([+-]\d{1,4})?\*\*/

  # First day of the week (as Time#wday) following Redmine's display setting,
  # falling back to the current language's default like Redmine's calendar.
  def self.first_weekday
    start = Setting.start_of_week.to_i
    start = ::I18n.t(:general_first_day_of_week, default: '1').to_i unless [1, 6, 7].include?(start)
    start % 7
  end

  def self.week_start_day
    Date::DAYNAMES[first_weekday].downcase.to_sym
  end

  # The seven weekdays starting on first_weekday, the order to display them in.
  def self.ordered_weekdays
    first = first_weekday
    WEEKDAYS.map { |i| (first + i) % 7 }
  end

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

  # Takes over the schedule and issue template of another task, leaving the
  # project and author of this one untouched.
  def copy_from(source)
    self.attributes = source.attributes.except(*COPY_EXCLUDED_ATTRIBUTES)
    self
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
    issue.fixed_version_id = fixed_version_id if fixed_version_id.present?
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

  # Earliest occurrence of the schedule after +now+. next_run_date is the
  # anchor (first run, time of day and cadence origin); when blank, +now+ is
  # the anchor and may itself be returned. Occurrences are derived from the
  # anchor rather than from +now+ so late scheduler runs do not drift.
  def get_next_run_date(now = Time.current)
    units = interval_units.downcase
    val = next_run_date || now
    if units == 'business_day'
      val = next_business_day_occurrence(val, now)
    elsif units == 'week' && weekdays.any?
      val = next_weekday_occurrence(val, now)
    elsif monthly_weekday_mode? && weekdays.any? && month_weeks.any?
      val = next_monthly_weekday_occurrence(val, now)
    else
      interval_steps = ((now - val) / interval_number.send(units)).ceil
      val += (interval_number * interval_steps).send(units)
    end
    val
  end

  private

  # Walks business days from the anchor's date and keeps the anchor's time of
  # day. business_time counts from the instant, so feeding it a time outside
  # business hours would move the occurrence to the start of a business day
  # (09:00 by default) and lose the scheduled time.
  def next_business_day_occurrence(anchor, now)
    date = anchor.to_date
    val = anchor
    while val <= now
      date = interval_number.business_days.after(date)
      val = at_anchor_time(date, anchor)
    end
    val
  end

  # Walks the eligible weeks (every interval_number weeks from the anchor's
  # week) and returns the first selected weekday, at the anchor's time of day,
  # that is due after +now+.
  def next_weekday_occurrence(anchor, now)
    week_start = anchor.beginning_of_week(self.class.week_start_day)
    offsets = weekdays.map { |wday| (wday - week_start.wday) % 7 }.sort
    each_eligible_period(anchor, now, 1.week) do |step|
      base = week_start + (step * interval_number).weeks
      candidates = offsets.map { |offset| at_anchor_time(base + offset.days, anchor) }
      candidates.find { |candidate| due?(candidate, now) }
    end
  end

  # Walks the eligible months (every interval_number months from the anchor's
  # month) and returns the earliest selected ordinal weekday, at the anchor's
  # time of day, that is due after +now+.
  def next_monthly_weekday_occurrence(anchor, now)
    each_eligible_period(anchor, now, 1.month) do |step|
      month = anchor.advance(months: step * interval_number).to_date.beginning_of_month
      candidates = month_weeks.product(weekdays).map { |ordinal, wday| nth_weekday_of_month(month, ordinal, wday) }
      candidates.uniq.sort.map { |date| at_anchor_time(date, anchor) }.find { |candidate| due?(candidate, now) }
    end
  end

  # Yields increasing period steps until the block returns an occurrence,
  # starting close to +now+ so long downtimes do not iterate over every period.
  def each_eligible_period(anchor, now, period)
    step = [((now - anchor) / (interval_number * period.to_i)).floor - 1, 0].max
    loop do
      occurrence = yield(step)
      return occurrence if occurrence

      step += 1
    end
  end

  # Date of the +ordinal+-th +wday+ in the month of +month+ (a first-of-month
  # Date); a missing fifth occurrence yields the last one.
  def nth_weekday_of_month(month, ordinal, wday)
    date = month + ((wday - month.wday) % 7) + ((ordinal - 1) * 7)
    date -= 7 while date.month != month.month
    date
  end

  def at_anchor_time(date, anchor)
    anchor.change(year: date.year, month: date.month, day: date.day)
  end

  # A stored next_run_date has already run, so the next one must be strictly
  # later than now; a blank one may resolve to now itself.
  def due?(candidate, now)
    next_run_date ? candidate > now : candidate >= now
  end

  def validate_recurrence
    return unless monthly_weekday_mode?

    errors.add(:base, l(:error_recurrence_month_weeks_blank)) if month_weeks.empty?
    errors.add(:base, l(:error_recurrence_weekdays_blank)) if weekdays.empty?
  end

  # Hidden recurrence inputs are still posted by the form; only keep the ones
  # that apply to the selected unit and monthly mode.
  def clear_irrelevant_recurrence_options
    self.monthly_mode = nil unless interval_units == 'month'
    self.month_weeks = [] unless monthly_weekday_mode?
    self.weekdays = [] unless interval_units == 'week' || monthly_weekday_mode?
  end

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
      next_month_time = now + 1.month
      next_week_time = now + 1.week
      str.gsub!('**DAY**', now.strftime('%d'))
      # The two week numbering systems do not share a year macro: %W counts weeks
      # within the calendar year and pairs with %Y, while %V counts ISO 8601 weeks
      # and pairs with the ISO year %G. The two drift apart around New Year, so
      # pairing an ISO week with **YEAR** is off by one on those dates.
      str.gsub!('**NEXT_WEEKISO_YEAR**', next_week_time.strftime('%G'))
      str.gsub!('**NEXT_WEEKISO**', next_week_time.strftime('%V'))
      str.gsub!('**NEXT_WEEK_YEAR**', next_week_time.strftime('%Y'))
      str.gsub!('**NEXT_WEEK**', next_week_time.strftime('%W'))
      str.gsub!('**WEEKISO_YEAR**', now.strftime('%G'))
      str.gsub!('**WEEKISO**', now.strftime('%V'))
      str.gsub!('**WEEK**', now.strftime('%W'))
      str.gsub!('**QUARTER**', (((now.month - 1) / 3) + 1).to_s)
      str.gsub!('**MONTHNAME**', I18n.localize(now, format: '%B'))
      str.gsub!('**MONTH**', now.strftime('%m'))
      # Year of the shifted month, not of the run time: **YEAR** next to a shifted
      # month macro is off by one in January and December.
      str.gsub!('**NEXT_MONTH_YEAR**', next_month_time.strftime('%Y'))
      str.gsub!('**PREVIOUS_MONTH_YEAR**', previous_month_time.strftime('%Y'))
      str.gsub!('**YEAR**', now.strftime('%Y'))
      str.gsub!('**PREVIOUS_MONTHNAME**', I18n.localize(previous_month_time, format: '%B'))
      str.gsub!('**PREVIOUS_MONTH**', previous_month_time.strftime('%m'))
      str.gsub!('**NEXT_MONTHNAME**', I18n.localize(next_month_time, format: '%B'))
      str.gsub!('**NEXT_MONTH**', next_month_time.strftime('%m'))
      str.gsub!(DATE_MACRO) do
        date_macro_value(Regexp.last_match(1), now + Regexp.last_match(2).to_i.days)
      end
    end
    str
  end

  def date_macro_value(name, time)
    case name
    when 'DAY' then time.strftime('%d')
    when 'WEEKISO' then time.strftime('%V')
    when 'WEEK' then time.strftime('%W')
    when 'QUARTER' then (((time.month - 1) / 3) + 1).to_s
    when 'MONTHNAME' then I18n.localize(time, format: '%B')
    when 'MONTH' then time.strftime('%m')
    when 'YEAR' then time.strftime('%Y')
    end
  end

  def fill_checklists(issue)
    return unless checklists_template_id && self.class.checklists_plugin_installed?

    template = ChecklistTemplate.find_by(id: checklists_template_id)
    return unless template

    issue.checklists_attributes = template.template_items.split("\n").each_with_index.map do |subject, position|
      { is_done: false, subject: subject, position: position }
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
