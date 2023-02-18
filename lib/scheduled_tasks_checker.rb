class ScheduledTasksChecker

  def self.checktasks!
    # replace variables (set locale from shell)
    I18n.locale = ENV['LOCALE'] || Setting.default_language || I18n.default_locale

    Time.zone = User.current.time_zone
    now = Time.zone.now
    Periodictask.where("(next_run_date <= ? OR next_run_date IS null) and is_disabled = ? ", now, false).each do |task|
      issue = task.generate_issue(now)
      if issue
        begin
          issue.save!
          task.last_error = nil
        rescue ActiveRecord::RecordInvalid => e
          Rails.logger.error "ScheduledTasksChecker: #{e.message}"
          "ScheduledTasksChecker: #{e.message}"
          task.last_error = e.message
        end
        task.next_run_date = Periodictask.get_next_run_date(task.next_run_date, task.interval_number, task.interval_units.downcase)
      else
        msg = "Project is missing or closed"
        Rails.logger.error "ScheduledTasksChecker: #{msg}"
        task.last_error = msg
      end
      task.save
    end
  end

end
