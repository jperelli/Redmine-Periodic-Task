class ScheduledTasksChecker
  # Runs every due task, records the run in PeriodictaskRun and returns how
  # many tasks were processed. +source+ tells the run log what triggered it
  # (see PeriodictaskRun::SOURCES).
  def self.checktasks!(source: 'rake')
    now = Time.current
    errors = []
    notes = []
    issues_created = 0
    tasks = Periodictask.active.where('next_run_date <= ? ', now).to_a

    # Macros render in the shell-configured locale (or Redmine's default). The
    # checker also runs inside web requests, so the caller's locale must be
    # restored afterwards.
    I18n.with_locale(ENV['LOCALE'] || I18n.default_locale) do
      tasks.each do |task|
        as_user(task.author) do
          run = TaskRun.new(task, now)
          run.execute
          issues_created += 1 if run.issue_created?
          errors.concat(run.errors)
          notes.concat(run.notes)
          task.save
        end
      end
    end
    tasks.size
  rescue StandardError => e
    errors << "#{e.class}: #{e.message}"
    raise
  ensure
    record_run(source, now, tasks, issues_created, errors, notes)
  end

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

    def create_issue(previous)
      issue = @task.generate_issue(@now)
      if issue
        begin
          issue.save!
          @issue_created = true
          @task.clear_skip
          task_errors = @task.complete_generated_issue(issue, @now)
          task_errors.concat(close_previous(previous, issue)) if previous
          task_errors.each { |msg| Rails.logger.error "ScheduledTasksChecker: #{msg}" }
          @errors.concat(task_errors.map { |msg| prefixed(msg) })
          @task.last_error = task_errors.join(', ').presence
        rescue ActiveRecord::RecordInvalid => e
          fail_with(e.message)
        end
        @task.next_run_date = @task.get_next_run_date(@now)
      else
        fail_with('Project is missing or closed')
      end
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
      @task.next_run_date = @task.get_next_run_date(@now) if @task.if_previous_open == 'skip'
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
