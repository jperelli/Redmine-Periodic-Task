module RedminePeriodictask
  # Lets an issue reach the periodic task that generated it (through the
  # PeriodictaskIssue join row), so the issue list can preload it for the
  # "Periodic task" column and the recurrence marker.
  module IssuePatch
    def self.included(base)
      base.class_eval do
        has_one :periodictask_issue
        has_one :periodictask, through: :periodictask_issue
      end
    end
  end
end
