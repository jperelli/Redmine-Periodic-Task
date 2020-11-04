class ScheduledTasksChecker
  def self.checktasks!
    now = Time.now
    Periodictask.where("next_run_date <= ? and is_disabled = ? ", now, 0).each do |task|

      # replace variables (set locale from shell)
      I18n.locale = ENV['LOCALE'] || I18n.default_locale

      issue = task.generate_issue(now)
      if issue
        begin
          issue.save!
          task.last_error = nil
        rescue ActiveRecord::RecordInvalid => e
          Rails.logger.error "ScheduledTasksChecker: #{e.message}"
          task.last_error = e.message
        end
        interval = task.interval_number
        units = task.interval_units.downcase
        if units == "business_day"
          task.next_run_date = task.interval_number.business_day.after(now)
        else
          interval_steps = ((now - task.next_run_date) / interval.send(units)).ceil
          task.next_run_date += (interval * interval_steps).send(units)
        end
      else
        msg = "Project is missing or closed"
        Rails.logger.error "ScheduledTasksChecker: #{msg}"
        task.last_error = msg
      end
      task.save
    end
  end
end
