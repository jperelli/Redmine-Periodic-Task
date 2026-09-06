require "#{File.dirname(__FILE__)}/../test_helper"

# A scheduled run is one unit of work per task: the issue, the occurrence
# count, the next run date and the end journal are committed together or not
# at all, and the row lock keeps overlapping triggers (cron, web scheduler,
# endpoint, Run now) from consuming the same occurrence twice.
class ScheduledRunAtomicityTest < ActiveSupport::TestCase
  fixtures :projects, :users, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :enabled_modules, :roles, :members, :member_roles

  # before_lock runs right before the row lock the checker takes on a task,
  # standing in for another trigger that gets to the task first; on_complete
  # runs once the issue is saved, right before the task finishes it.
  cattr_accessor :before_lock, :on_complete
  Periodictask.prepend(Module.new do
    def with_lock(*args, &)
      ScheduledRunAtomicityTest.before_lock&.call(self)
      super
    end

    def complete_generated_issue(issue, now = Time.current)
      ScheduledRunAtomicityTest.on_complete&.call(self)
      super
    end
  end)

  def setup
    @project = Project.find(1)
    EnabledModule.create!(project: @project, name: 'periodictask')
    User.current = nil
  end

  def teardown
    self.class.before_lock = nil
    self.class.on_complete = nil
  end

  # ---- rollback ----

  def test_failure_after_the_issue_is_saved_rolls_back_the_issue_and_the_count
    task = create_task(max_occurrences: 1)
    next_run = task.next_run_date
    self.class.on_complete = ->(_task) { raise 'boom' }

    assert_no_difference(['Issue.count', 'PeriodictaskIssue.count', 'PeriodictaskJournal.count']) do
      ScheduledTasksChecker.checktasks!
    end

    task.reload
    assert_equal 0, task.occurrences_count
    assert_equal next_run.to_i, task.next_run_date.to_i
    assert_not task.ended?
    assert_equal 'RuntimeError: boom', task.last_error
    assert_match(/##{task.id} Atomic run: RuntimeError: boom/, PeriodictaskRun.order(:id).last.error_messages)
  end

  def test_failure_to_write_the_end_journal_rolls_back_the_final_run
    task = create_task(max_occurrences: 1)
    PeriodictaskJournal.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid.new(PeriodictaskJournal.new))

    assert_no_difference(['Issue.count', 'PeriodictaskJournal.count']) { ScheduledTasksChecker.checktasks! }

    task.reload
    assert_equal 0, task.occurrences_count
    assert_not task.ended?
    assert task.due_by?(Time.current)
  end

  def test_failure_to_save_the_task_rolls_back_the_issue
    task = create_task
    Periodictask.any_instance.stubs(:save_run!).raises(ActiveRecord::StatementInvalid, 'lost connection')

    assert_no_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    assert_equal 0, task.reload.occurrences_count
  end

  def test_a_failing_task_does_not_stop_the_other_due_tasks
    failing = create_task(subject: 'Failing')
    healthy = create_task(subject: 'Healthy')
    self.class.on_complete = ->(task) { raise 'boom' if task.id == failing.id }

    processed = ScheduledTasksChecker.checktasks!

    assert_equal 2, processed
    assert_equal 0, failing.reload.occurrences_count
    assert_equal 1, healthy.reload.occurrences_count
    assert_equal 1, healthy.created_issues.count
    assert_match(/boom/, failing.last_error)
    assert_nil healthy.last_error
  end

  def test_successful_run_commits_issue_count_schedule_and_journal_together
    task = create_task(max_occurrences: 1)

    assert_difference(['Issue.count', 'PeriodictaskIssue.count', 'PeriodictaskJournal.count']) do
      ScheduledTasksChecker.checktasks!
    end

    task.reload
    assert_equal 1, task.occurrences_count
    assert task.next_run_date > Time.current
    assert_equal 'ended_by_count', task.end_reason
  end

  # ---- overlapping triggers ----

  def test_two_overlapping_checkers_consume_a_single_occurrence
    task = create_task(max_occurrences: 1)
    first = true
    self.class.before_lock = lambda do |locked|
      next unless first && locked.id == task.id

      first = false
      ScheduledTasksChecker.checktasks!(source: 'web')
    end

    assert_difference('Issue.count', 1) { ScheduledTasksChecker.checktasks! }

    task.reload
    assert_equal 1, task.occurrences_count
    assert task.ended?
    assert_equal ['ended_by_count'], PeriodictaskJournal.where(periodictask_id: task.id).pluck(:action)
    runs = PeriodictaskRun.order(:id).last(2)
    assert_equal %w[web rake], runs.map(&:source)
    assert_equal [1, 0], runs.map(&:issues_created)
  end

  def test_checker_does_not_run_a_task_another_trigger_advanced_before_the_lock
    task = create_task(max_occurrences: 3)
    while_locking(task) do
      Periodictask.where(id: task.id).update_all(next_run_date: 1.day.from_now, occurrences_count: 1)
    end

    assert_no_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    assert_equal 1, task.reload.occurrences_count
  end

  def test_checker_does_not_run_a_task_that_ended_before_the_lock
    task = create_task(max_occurrences: 1)
    while_locking(task) { Periodictask.where(id: task.id).update_all(occurrences_count: 1) }

    assert_no_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    assert_equal 1, task.reload.occurrences_count
  end

  def test_checker_does_not_run_a_task_deactivated_before_the_lock
    task = create_task
    while_locking(task) { Periodictask.where(id: task.id).update_all(is_active: false) }

    assert_no_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    assert_equal 0, task.reload.occurrences_count
  end

  def test_run_now_before_the_lock_does_not_consume_the_scheduled_occurrence
    task = create_task(max_occurrences: 1)
    while_locking(task) do
      other = Periodictask.find(task.id)
      issue = other.generate_issue
      issue.save!
      other.complete_generated_issue(issue)
    end

    assert_difference('Issue.count', 2) { ScheduledTasksChecker.checktasks! }

    task.reload
    assert_equal 1, task.occurrences_count
    assert_equal 2, task.created_issues.count
    assert task.ended?
  end

  private

  def create_task(attrs = {})
    Periodictask.create!({
      project: @project, tracker_id: 1, assigned_to_id: 2, author_id: 1,
      subject: 'Atomic run', interval_number: 1, interval_units: 'day',
      next_run_date: 1.hour.ago
    }.merge(attrs))
  end

  def while_locking(task, &block)
    self.class.before_lock = ->(locked) { block.call if locked.id == task.id }
  end
end
