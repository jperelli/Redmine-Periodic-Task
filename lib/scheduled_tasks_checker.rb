class ScheduledTasksChecker
  def self.checktasks!
    now = Time.now
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
        task.next_run_date = task.get_next_run_date(now)
      else
        msg = "Project is missing or closed"
        Rails.logger.error "ScheduledTasksChecker: #{msg}"
        task.last_error = msg
      end
      task.save
    end
  end
end
