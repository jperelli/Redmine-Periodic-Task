class Periodictask < ActiveRecord::Base
  unloadable
  belongs_to :project
  belongs_to :assigned_to, :class_name => 'Principal', :foreign_key => 'assigned_to_id'
  belongs_to :issue_category, :class_name => 'IssueCategory', :foreign_key => 'issue_category_id'
  serialize :custom_field_values
  # adapted to changes concerning mass-assigning values to attributes
  #attr_accessible *column_names
  # the above (attr_accessible *column_names) does not work for some reason
  attr_protected
  INTERVAL_UNITS = [
    [l(:label_unit_day), 'day'],
    [l(:label_unit_business_day), 'business_day'],
    [l(:label_unit_week), 'week'], 
    [l(:label_unit_month), 'month'],
    [l(:label_unit_year), 'year']
  ]

  def generate_issue(now = Time.now)
    # Copy subject and description and replace variables
    subj = subject.dup rescue nil
    if subj.present?
      subj.gsub!('**DAY**', now.strftime("%d"))
      subj.gsub!('**WEEK**', now.strftime("%W"))
      subj.gsub!('**MONTH**', now.strftime("%m"))
      subj.gsub!('**MONTHNAME**', I18n.localize(now, :format => "%B"))
      subj.gsub!('**YEAR**', now.strftime("%Y"))
      subj.gsub!('**PREVIOUS_MONTHNAME**', I18n.localize(now - 2592000, :format => "%B"))
      subj.gsub!('**PREVIOUS_MONTH**', I18n.localize(now - 2592000, :format => "%m"))
    end
    desc = description.dup rescue nil
    if desc.present?
      desc.gsub!('**DAY**', now.strftime("%d"))
      desc.gsub!('**WEEK**', now.strftime("%W"))
      desc.gsub!('**MONTH**', now.strftime("%m"))
      desc.gsub!('**MONTHNAME**', I18n.localize(now, :format => "%B"))
      desc.gsub!('**YEAR**', now.strftime("%Y"))
      desc.gsub!('**PREVIOUS_MONTHNAME**', I18n.localize(now - 2592000, :format => "%B"))
      desc.gsub!('**PREVIOUS_MONTH**', I18n.localize(now - 2592000, :format => "%m"))
    end

    issue = Issue.new(:project_id => project_id, :tracker_id => tracker_id || project.trackers.first.try(:id), :category_id => issue_category_id,
                      :assigned_to_id => assigned_to_id, :author_id => author_id,
                      :subject => subj, :description => desc)
    issue.start_date ||= Date.today if set_start_date?
    if due_date_number
      due_date = due_date_number
      due_date_units = due_date_units || 'day'
      issue.due_date = due_date.send(due_date_units.downcase).from_now
    end
    issue.custom_field_values = custom_field_values if custom_field_values.is_a?(Hash)

    issue
  end
end
