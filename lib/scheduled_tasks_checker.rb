class ScheduledTasksChecker
  def self.checktasks!
    now = Time.current
    Periodictask.where('next_run_date <= ? ', now).each do |task|
      # replace variables (set locale from shell)
      I18n.locale = ENV['LOCALE'] || I18n.default_locale

      as_user(task.author) do
        issue = task.generate_issue(now)
        if issue
          begin
            issue.save!
            task.fill_watchers(issue)
            task.record_generated_issue(issue)
            task.last_error = nil
          rescue ActiveRecord::RecordInvalid => e
            Rails.logger.error "ScheduledTasksChecker: #{e.message}"
            task.last_error = e.message
          end
          task.next_run_date = task.get_next_run_date(now)
        else
          msg = 'Project is missing or closed'
          Rails.logger.error "ScheduledTasksChecker: #{msg}"
          task.last_error = msg
        end
        task.save
      end
    end
  end

  # Runs the block with User.current set to +user+ so permission-based
  # validations (Redmine's own and other plugins', e.g. Luxury Buttons'
  # per-tracker role restrictions) evaluate against the task author rather
  # than Anonymous, which is what User.current resolves to under rake/cron.
  def self.as_user(user)
    previous = User.current
    User.current = user if user
    yield
  ensure
    User.current = previous
  end
end
