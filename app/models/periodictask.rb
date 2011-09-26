class Periodictask < ActiveRecord::Base
  unloadable
  belongs_to :project
  INTERVAL_UNITS = ['day','week', 'month']
end
