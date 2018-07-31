class Periodictask < ActiveRecord::Base
  unloadable
  belongs_to :project
  belongs_to :assigned_to, :class_name => 'Principal', :foreign_key => 'assigned_to_id'
  belongs_to :issue_category, :class_name => 'IssueCategory', :foreign_key => 'issue_category_id'
  attr_accessible *column_names
  INTERVAL_UNITS = [
    [l(:label_unit_day), 'day'],
    [l(:label_unit_business_day), 'business_day'],
    [l(:label_unit_week), 'week'],
    [l(:label_unit_month), 'month'],
    [l(:label_unit_year), 'year']
  ]
  DUE_DATE_UNITS = [
    [l(:label_later_day), 'day'],
    [l(:label_later_business_day), 'business_day'],
    [l(:label_later_week), 'week'],
    [l(:label_later_month), 'month'],
    [l(:label_later_year), 'year']
  ]
end
