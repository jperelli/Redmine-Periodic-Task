class ScheduledTasksChecker
  # Runs every due task, records the run in PeriodictaskRun and returns how
  # many tasks were processed. +source+ tells the run log what triggered it
  # (see PeriodictaskRun::SOURCES).
  def self.checktasks!(source: 'rake')
    now = Time.current
    errors = []
    notes = []
    issues_created = 0
    tasks = Periodictask.runnable.possibly_due(now).select { |task| task.due_by?(now) }

    # Macros render in the shell-configured locale (or Redmine's default). The
    # checker also runs inside web requests, so the caller's locale must be
    # restored afterwards.
    I18n.with_locale(ENV['LOCALE'] || I18n.default_locale) do
      tasks.each do |task|
        run = run_task(task, now)
        next unless run

        issues_created += 1 if run.issue_created?
        errors.concat(run.errors)
        notes.concat(run.notes)
      rescue ActiveRecord::RecordNotFound
        # Deleted since the query above; anything else missing is a real error.
        raise if Periodictask.exists?(task.id)

        Rails.logger.info "ScheduledTasksChecker: ##{task.id} was deleted before it could run"
      rescue StandardError => e
        # The transaction rolled back: no issue, no count, no schedule change.
        # The task keeps the error and the other due tasks still run.
        message = "##{task.id} #{task.subject}: #{e.class}: #{e.message}"
        Rails.logger.error "ScheduledTasksChecker: #{message}"
        errors << message
        task.update_columns(last_error: "#{e.class}: #{e.message}")
      end
    end
    tasks.size
  rescue StandardError => e
    errors << "#{e.class}: #{e.message}"
    raise
  ensure
    record_run(source, now, tasks, issues_created, errors, notes)
  end

  # One task's run, as a unit: cron, the web scheduler, the endpoint and Run
  # now can fire together, so the row is locked (with_lock: transaction +
  # SELECT FOR UPDATE) from generating the issue until the task (schedule,
  # count, rotation position) and the end journal are saved. lock! reloads the
  # task, so a task another trigger just ran or ended is seen as such and
  # skipped; a failure anywhere rolls the issue back along with the count.
  # Returns the TaskRun, or nil when the task was not run.
  def self.run_task(task, now)
    task.with_lock do
      next unless task.runnable? && task.due_by?(now)

      as_user(task.author) do
        run = TaskRun.new(task, now)
        run.execute
        finish(task) if task.ended?
        task.save_run!
        run
      end
    end
  end
  private_class_method :run_task

  # Records in the activity log that the run just made was the last one. The
  # task is ended by its own end condition from now on (Periodictask#ended?);
  # nothing else is stored.
  def self.finish(task)
    reason = task.end_reason
    Rails.logger.info "ScheduledTasksChecker: ##{task.id} #{task.subject} #{reason.tr('_', ' ')}"
    task.log_activity(reason)
  end
  private_class_method :finish

  def self.record_run(source, now, tasks, issues_created, errors, notes)
    PeriodictaskRun.record!(source: source, started_at: now, finished_at: Time.current,
                            tasks_due: tasks.to_a.size, issues_created: issues_created.to_i,
                            errors: errors.to_a, notes: notes.to_a)
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

  # One due task's run: decides, from the task's if_previous_open mode and the
  # state of the issue it generated last time, whether to create an issue,
  # skip this occurrence or wait, and updates the task accordingly (schedule,
  # last_error, last skip). The task is not saved here.
  class TaskRun
    include Redmine::I18n

    attr_reader :errors, :notes

    def initialize(task, now)
      @task = task
      @now = now
      @errors = []
      @notes = []
      @issue_created = false
    end

    def issue_created?
      @issue_created
    end

    def execute
      previous = @task.open_previous_issue
      if previous && @task.waits_for_previous_issue?
        skip(previous)
      elsif @task.if_previous_open == 'after_completion' && (resume_at = resume_after_completion)
        reschedule(resume_at)
      else
        create_issue(previous)
      end
    end

    private

    # An issue that fails to save costs the occurrence (the schedule moves on,
    # the error is kept on the task). Once it is saved, the occurrence is
    # consumed: anything raised after that point is left to the caller's
    # transaction, which takes the issue back along with the count.
    def create_issue(previous)
      issue = @task.generate_issue(@now)
      return fail_with(l(:label_project_missing_or_closed)) unless issue

      begin
        issue.save!
      rescue ActiveRecord::RecordInvalid => e
        fail_with(e.message)
        return advance_schedule
      end

      @issue_created = true
      @task.occurrences_count += 1
      @task.clear_skip
      task_errors = @task.complete_generated_issue(issue, @now)
      task_errors.concat(close_previous(previous, issue)) if previous
      task_errors.each { |msg| Rails.logger.error "ScheduledTasksChecker: #{msg}" }
      @errors.concat(task_errors.map { |msg| prefixed(msg) })
      @task.last_error = task_errors.join(', ').presence
      advance_schedule
    end

    # close_previous: the previous issue is closed once the new one exists, so
    # a failure to close it never costs the new occurrence.
    def close_previous(previous, issue)
      failures = @task.close_generated_issue(previous, l(:text_periodictask_closed_by_next_issue, id: issue.id))
      failures.map { |msg| "#{l(:label_periodictask_close_previous_failed)} #{msg}" }
    end

    # skip advances the schedule (this occurrence is lost); after_completion
    # keeps the task due until the previous issue is closed.
    def skip(previous)
      @task.record_skip(previous, @now)
      @task.last_error = nil
      advance_schedule if @task.if_previous_open == 'skip'
      note(l(:text_periodictask_skipped_open_issue, id: previous.id))
    end

    # after_completion, previous issue closed: the next occurrence counted from
    # its closing day, when that is still ahead of us (otherwise it is due now).
    def resume_after_completion
      previous = @task.last_generated_issue
      return unless previous&.closed?

      resume_at = @task.next_run_date_after_completion(previous.closed_on || previous.updated_on)
      resume_at if resume_at > @now
    end

    def reschedule(resume_at)
      @task.clear_skip
      @task.last_error = nil
      @task.next_run_date = resume_at
      note(l(:text_periodictask_rescheduled_after_completion,
             id: @task.last_generated_issue.id, time: format_time(resume_at)))
    end

    # A run moved to a previous working day fires before its stored occurrence;
    # the next one must follow that occurrence, not now.
    def advance_schedule
      @task.next_run_date = @task.get_next_run_date([@now, @task.next_run_date].max)
    end

    def fail_with(message)
      Rails.logger.error "ScheduledTasksChecker: #{message}"
      @errors << prefixed(message)
      @task.last_error = message
    end

    def note(message)
      Rails.logger.info "ScheduledTasksChecker: #{prefixed(message)}"
      @notes << prefixed(message)
    end

    def prefixed(message)
      "##{@task.id} #{@task.subject}: #{message}"
    end
  end
end
