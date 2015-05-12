class Periodictask < ActiveRecord::Base
  unloadable
  belongs_to :project
  INTERVAL_UNITS = [
    [l(:label_unit_day), 'day'],
    [l(:label_unit_week), 'week'], 
    [l(:label_unit_month), 'month'],
    [l(:label_unit_year), 'year']
  ]
end
