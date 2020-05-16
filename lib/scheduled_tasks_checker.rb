class ScheduledTasksChecker

  def self.checktasks!
    Time.zone = User.current.time_zone
    now = Time.zone.now
    Periodictask.where("next_run_date <= ? ", now).each do |task|

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
          next_run_date = task.interval_number.business_day.after(Time.zone.now)
        else
          interval_steps = ((now - task.next_run_date) / interval.send(units)).ceil
          next_run_date += (interval * interval_steps).send(units)
        end
        next_run_date = next_run_date.change({ hour: Time.zone.now.hour.to_i, min: Time.zone.now.min.to_i, sec: Time.zone.now.sec.to_i })
        task.next_run_date = next_run_date
      else
        msg = "Project is missing or closed"
        Rails.logger.error "ScheduledTasksChecker: #{msg}"
        task.last_error = msg
      end
      task.save
    end
  end
end
