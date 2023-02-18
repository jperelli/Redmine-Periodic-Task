class Periodictask < ActiveRecord::Base
  unloadable
  belongs_to :project
  belongs_to :tracker
  belongs_to :assigned_to, :class_name => 'Principal', :foreign_key => 'assigned_to_id'
  belongs_to :issue_category, :class_name => 'IssueCategory', :foreign_key => 'issue_category_id'
  belongs_to :version, :class_name => 'Version', :foreign_key => 'version_id'
  serialize :custom_field_values
  # adapted to changes concerning mass-assigning values to attributes
  #attr_accessible *column_names
  # the above (attr_accessible *column_names) does not work for some reason
  attr_protected

  after_initialize do |task|
    if task.new_record?
      task.interval_number ||= 1
      task.interval_units ||= INTERVAL_UNITS.first[1];
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

  def generate_issue(now = Time.now)
    Time.zone = User.current.time_zone
    if project.try(:active?)
      # Copy subject and description and replace variables
      v_id = version_id
      subj = parse_macro(subject.try(:dup), now)
      desc = parse_macro(description.try(:dup), now)
      version_name = parse_macro(version_name.try(:dup), now)

      if version_name.present?
        v = Project.find(task.project_id).shared_versions.where(name: version_name).first
        v_id = v.id if v.present?
      end
      #trace "Version: #{v_id}. Name: #{version_name}. Tracker: #{task.tracker_id}"
      issue = Issue.new(:project_id => project_id, :tracker_id => tracker_id || project.trackers.first.try(:id), :category_id => issue_category_id,
                        :assigned_to_id => assigned_to_id, :author_id => author_id,
                        :subject => subj, :description => desc)
      issue.start_date ||= now.to_date if set_start_date?
      issue.fixed_version = Version.find(v_id) if v_id.present?
      if due_date_number
        due_date = due_date_number
        due_date_unit = due_date_units || 'day'
        issue.due_date = due_date.send(due_date_unit.downcase).from_now
      end
      issue.estimated_hours = estimated_hours

      fill_checklists issue
      fill_custom_fields issue

      issue
    end
  end

  def self.get_next_run_date(prev_run_date, interval, units)
    if units == "business_day"
      next_run_date = interval.business_day.after(Time.zone.now)
    else
      if prev_run_date
        interval_steps = (( Time.zone.now - prev_run_date) / interval.send(units)).ceil
        next_run_date = prev_run_date + (interval * interval_steps).send(units)
        next_run_date.change({ hour: prev_run_date.hour.to_i, min: prev_run_date.min.to_i, sec: prev_run_date.sec.to_i })
      else
        next_run_date =  Time.zone.now
      end
    end
    next_run_date
  end

  private
  def parse_macro(str, now)
    if str.respond_to?(:gsub!) && str.present?
      str.gsub!('**DAY**', now.strftime("%d"))
      str.gsub!('**WEEK**', now.strftime("%W"))
      str.gsub!('**MONTH**', now.strftime("%m"))
      str.gsub!('**MONTHNAME**', I18n.localize(now, :format => "%B"))
      str.gsub!('**YEAR**', now.strftime("%Y"))
      str.gsub!('**PREVIOUS_MONTHNAME**', I18n.localize(Time.now - 1.month, :format => "%B"))
      str.gsub!('**PREVIOUS_MONTH**', I18n.localize(Time.now - 1.month, :format => "%m"))
      str.gsub!('**NEXT_MONTHNAME**', I18n.localize(Time.now + 1.month, :format => "%B"))
      str.gsub!('**NEXT_MONTH**', I18n.localize(Time.now + 1.month, :format => "%m"))
    end
    str
  end

  def fill_checklists(issue)
    if PeriodictaskHelper.checklist_plugin_installed? && checklists_template_id
      template = ChecklistTemplate.find(checklists_template_id)
      if template
        items = template.template_items.split("\n")
        checklists = items.each_with_index.map { |x, i| {
          :is_done => false,
          :subject => x,
          :position => i
        }}
        issue.checklists_attributes = checklists
      end
    end
  end

  def fill_custom_fields(issue)
    issue.custom_field_values = custom_field_values.to_unsafe_hash if custom_field_values.respond_to?(:to_unsafe_hash)
  end

  DUE_DATE_UNITS = [
    [l(:label_later_day), 'day'],
    [l(:label_later_business_day), 'business_day'],
    [l(:label_later_week), 'week'],
    [l(:label_later_month), 'month'],
    [l(:label_later_year), 'year']
  ]

end
