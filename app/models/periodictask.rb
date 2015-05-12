class Periodictask < ActiveRecord::Base
  unloadable
  belongs_to :project
  # adapted to changes concerning mass-assigning values to attributes
  attr_accessible *column_names
  INTERVAL_UNITS = [
    [l(:label_unit_day), 'day'],
    [l(:label_unit_week), 'week'], 
    [l(:label_unit_month), 'month'],
    [l(:label_unit_year), 'year']
  ]
end
