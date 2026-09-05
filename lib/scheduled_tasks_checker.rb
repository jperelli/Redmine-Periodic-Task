class ScheduledTasksChecker
  # Runs every due task, records the run in PeriodictaskRun and returns how
  # many tasks were processed. +source+ tells the run log what triggered it
  # (see PeriodictaskRun::SOURCES).
  def self.checktasks!(source: 'rake')
    now = Time.current
    errors = []
    issues_created = 0
    tasks = Periodictask.active.where('next_run_date <= ? ', now).to_a

    # Macros render in the shell-configured locale (or Redmine's default). The
    # checker also runs inside web requests, so the caller's locale must be
    # restored afterwards.
    I18n.with_locale(ENV['LOCALE'] || I18n.default_locale) do
      tasks.each do |task|
        as_user(task.author) do
          # A task edited past its end (e.g. max_occurrences lowered below the
          # runs already made) ends without creating another issue.
          issues_created += run_task(task, now, errors) unless task.end_reached?
          finish(task) if task.end_reached?
          task.save
        end
      end
    end
    tasks.size
  rescue StandardError => e
    errors << "#{e.class}: #{e.message}"
    raise
  ensure
    record_run(source, now, tasks, issues_created, errors)
  end

  # Creates the issue of one due task and moves it to its next run. Returns
  # the number of issues created (0 or 1); failures go to +errors+ and to the
  # task's last_error.
  def self.run_task(task, now, errors)
    issue = task.generate_issue(now)
    unless issue
      msg = 'Project is missing or closed'
      Rails.logger.error "ScheduledTasksChecker: #{msg}"
      errors << "##{task.id} #{task.subject}: #{msg}"
      task.last_error = msg
      return 0
    end

    created = 0
    begin
      issue.save!
      created = 1
      task.occurrences_count += 1
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
    created
  end
  private_class_method :run_task

  # Disables a task whose end condition is met and records why in the
  # activity log; the schedule is left untouched so no further run is queued.
  def self.finish(task)
    reason = task.end_reason
    Rails.logger.info "ScheduledTasksChecker: ##{task.id} #{task.subject} #{reason.tr('_', ' ')}"
    task.mark_ended(reason)
  end
  private_class_method :finish

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
