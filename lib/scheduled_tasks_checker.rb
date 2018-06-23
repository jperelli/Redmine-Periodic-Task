class ScheduledTasksChecker
  def self.checktasks!
    now = Time.now
    Periodictask.where("next_run_date <= ? ", now).each do |task| 

      # replace variables (set locale from shell)
      I18n.locale = ENV['LOCALE'] || I18n.default_locale

      issue = task.generate_issue(now)
      begin
        issue.save!
        task.last_error = nil unless task.last_error.blank?
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "ScheduledTasksChecker: #{e.message}"
        task.last_error = e.message
      end
      interval = task.interval_number
      units = task.interval_units

      if units.downcase == "business_day"
        task.next_run_date = task.interval_number.business_day.after(now)
      else
        if (interval > 0)
          interval_steps = ((now - task.next_run_date) / interval.send(units.downcase)).ceil
          task.next_run_date += (interval * interval_steps).send(units.downcase)
        end
      end
      task.save
    end
  end
end
