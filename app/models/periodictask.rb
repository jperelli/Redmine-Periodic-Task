class Periodictask < ActiveRecord::Base
  include Redmine::I18n

  belongs_to :project
  belongs_to :assigned_to, class_name: 'Principal', foreign_key: 'assigned_to_id'
  belongs_to :issue_category, class_name: 'IssueCategory', foreign_key: 'issue_category_id'
  serialize :custom_field_values
  attribute :watcher_user_ids, :json, default: []

  def watcher_user_ids=(value)
    super(Array(value).map(&:to_i).reject(&:zero?))
  end

  after_initialize do |task|
    if task.new_record?
      task.interval_number ||= 1
      task.interval_units ||= INTERVAL_UNITS.first[1]
    end
  end

  validates :interval_number, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :interval_units, presence: true

  scope :accessible, lambda {
    if User.current.allowed_to?(:periodictask, nil, global: true)
      all
    else
      where('1 = 0')
    end
  }

  INTERVAL_UNITS = [
    [l(:label_unit_day), 'day'],
    [l(:label_unit_business_day), 'business_day'],
    [l(:label_unit_week), 'week'],
    [l(:label_unit_month), 'month'],
    [l(:label_unit_year), 'year']
  ]

  def generate_issue(now = Time.current)
    return unless project.try(:active?)

    # Copy subject and description and replace variables
    subj = parse_macro(subject.try(:dup), now)
    desc = parse_macro(description.try(:dup), now)

    issue = Issue.new(project_id: project_id, tracker_id: tracker_id || project.trackers.first.try(:id), category_id: issue_category_id, parent_id: parent_id,
                      assigned_to_id: assigned_to_id, author_id: author_id,
                      subject: subj, description: desc)
    issue.priority_id = priority_id if priority_id.present?
    issue.start_date ||= now.to_date if set_start_date?
    if due_date_number
      due_date = due_date_number
      due_date_units ||= 'day'
      issue.due_date = due_date.send(due_date_units.downcase).from_now
    end
    issue.estimated_hours = estimated_hours

    fill_checklists issue
    fill_custom_fields issue

    issue
  end

  def fill_watchers(issue)
    return if watcher_user_ids.blank?
    return unless issue.persisted?

    watcher_user_ids.each do |uid|
      uid = uid.to_i
      next if uid == 0

      user = User.find_by(id: uid)
      issue.add_watcher(user) if user
    end
  end

  def get_next_run_date(now = Time.current)
    units = interval_units.downcase
    val = next_run_date || now
    if units == 'business_day'
      while val <= now
        val = interval_number.business_day.after(val)
      end
    else
      interval_steps = ((now - val) / interval_number.send(units)).ceil
      val += (interval_number * interval_steps).send(units)
    end
    val
  end

  private

  def parse_macro(str, now)
    if str.respond_to?(:gsub!) && str.present?
      previous_month_time = now - 1.month
      str.gsub!('**DAY**', now.strftime('%d'))
      str.gsub!('**WEEKISO**', now.strftime('%V'))
      str.gsub!('**WEEK**', now.strftime('%W'))
      str.gsub!('**QUARTER**', ((now.month - 1) / 3 + 1).to_s)
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

  def fill_custom_fields(issue)
    issue.custom_field_values = custom_field_values.to_unsafe_hash if custom_field_values.respond_to?(:to_unsafe_hash)
  end
end
