class ScheduledTasksChecker
  # Runs every due task, records the run in PeriodictaskRun and returns how
  # many tasks were processed. +source+ tells the run log what triggered it
  # (see PeriodictaskRun::SOURCES).
  def self.checktasks!(source: 'rake')
    now = Time.current
    errors = []
    issues_created = 0
    tasks = Periodictask.where('next_run_date <= ? ', now).to_a

    tasks.each do |task|
      # replace variables (set locale from shell)
      I18n.locale = ENV['LOCALE'] || I18n.default_locale

      as_user(task.author) do
        issue = task.generate_issue(now)
        if issue
          begin
            issue.save!
            issues_created += 1
            task_errors = task.complete_generated_issue(issue, now)
            task_errors.each { |msg| Rails.logger.error "ScheduledTasksChecker: #{msg}" }
            errors.concat(task_errors.map { |msg| "##{task.id} #{task.subject}: #{msg}" })
            task.last_error = task_errors.join(', ').presence
          rescue ActiveRecord::RecordInvalid => e
            Rails.logger.error "ScheduledTasksChecker: #{e.message}"
            errors << "##{task.id} #{task.subject}: #{e.message}"
            task.last_error = e.message
          end
          task.next_run_date = task.get_next_run_date(now)
        else
          msg = 'Project is missing or closed'
          Rails.logger.error "ScheduledTasksChecker: #{msg}"
          errors << "##{task.id} #{task.subject}: #{msg}"
          task.last_error = msg
        end
        task.save
      end
    end
    tasks.size
  rescue StandardError => e
    errors << "#{e.class}: #{e.message}"
    raise
  ensure
    record_run(source, now, tasks, issues_created, errors)
  end

  def self.record_run(source, now, tasks, issues_created, errors)
    PeriodictaskRun.record!(source: source, started_at: now, finished_at: Time.current,
                            tasks_due: tasks.to_a.size, issues_created: issues_created.to_i,
                            errors: errors.to_a)
  rescue StandardError => e
    Rails.logger.error "ScheduledTasksChecker: could not record run: #{e.class}: #{e.message}"
  end
  private_class_method :record_run

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
