# Join record linking a Periodictask to each Issue it has generated,
# so the periodic task detail page can show its run history.
class PeriodictaskIssue < ActiveRecord::Base
  belongs_to :periodictask
  belongs_to :issue

  before_create { self.created_at ||= Time.current }
end
