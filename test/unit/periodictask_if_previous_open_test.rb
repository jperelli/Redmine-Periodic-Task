require "#{File.dirname(__FILE__)}/../test_helper"

# Checker behaviour of the if_previous_open modes, with real generated issues.
class PeriodictaskIfPreviousOpenTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :enabled_modules, :roles, :members, :member_roles, :workflows

  def setup
    @project = Project.find(1)
    EnabledModule.create!(project: @project, name: 'periodictask')
    Periodictask.delete_all
    PeriodictaskRun.delete_all
  end

  def create_task(attrs = {})
    Periodictask.create!({ project: @project, tracker_id: 1, author_id: 2, assigned_to_id: 2,
                           subject: 'Weekly report', interval_number: 1, interval_units: 'week',
                           next_run_date: 1.day.ago }.merge(attrs))
  end

  # Runs the checker with the task due (at +at+) and returns the top-level
  # issue it created, if any.
  def run_due(task, at: 1.hour.ago)
    task.update_columns(next_run_date: at)
    before = task.created_issues.to_a
    ScheduledTasksChecker.checktasks!
    task.reload
    created = task.created_issues.to_a - before
    created.find { |issue| created.none? { |parent| parent.id == issue.parent_id } }
  end

  def close(issue, at = Time.current)
    issue.reload
    issue.status = IssueStatus.where(is_closed: true).sorted.first
    issue.save!
    issue.update_columns(closed_on: at)
    issue.reload
  end

  def last_run
    PeriodictaskRun.recent.first
  end

  # --- model -------------------------------------------------------------

  def test_defaults_to_create_and_rejects_unknown_modes
    assert_equal 'create', Periodictask.new.if_previous_open
    assert_equal 'create', create_task.if_previous_open
    task = Periodictask.new(project: @project, tracker_id: 1, author_id: 2, subject: 'x', if_previous_open: 'maybe')
    assert_not task.valid?
    assert task.errors[:if_previous_open].any?
  end

  def test_blank_mode_falls_back_to_create
    task = create_task(if_previous_open: '')
    assert_equal 'create', task.reload.if_previous_open
  end

  def test_last_generated_issue_is_the_newest_top_level_issue
    task = create_task(subtasks: [{ 'subject' => 'Child' }])
    assert_nil task.last_generated_issue

    first = run_due(task)
    second = run_due(task)
    assert_equal 4, task.created_issues.count
    assert_equal second, task.last_generated_issue

    second.destroy
    assert_equal first, task.reload.last_generated_issue
  end

  def test_open_previous_issue_ignores_closed_issues_and_create_mode
    task = create_task(if_previous_open: 'skip')
    issue = run_due(task)
    assert_equal issue, task.open_previous_issue

    task.update_columns(if_previous_open: 'create')
    assert_nil task.reload.open_previous_issue

    task.update_columns(if_previous_open: 'skip')
    close(issue)
    assert_nil task.reload.open_previous_issue
  end

  def test_copy_takes_the_mode_but_not_the_last_skip
    source = create_task(if_previous_open: 'skip', last_skipped_issue_id: 42, last_skipped_at: Time.current)
    copy = Periodictask.new(project: @project, author_id: 1).copy_from(source)
    assert_equal 'skip', copy.if_previous_open
    assert_nil copy.last_skipped_issue_id
    assert_nil copy.last_skipped_at
  end

  # --- create (default) ----------------------------------------------------

  def test_create_mode_generates_an_issue_even_when_the_previous_one_is_open
    task = create_task
    first = run_due(task)
    second = run_due(task)
    assert_not_equal first, second
    assert_not first.reload.closed?
    assert_nil task.last_skipped_at
    assert_nil last_run.notes
  end

  # --- skip ----------------------------------------------------------------

  def test_skip_mode_creates_nothing_and_advances_the_schedule_while_previous_is_open
    task = create_task(if_previous_open: 'skip')
    first = run_due(task)

    assert_no_difference('Issue.count') { assert_nil run_due(task) }
    assert task.next_run_date > Time.current, 'the skipped occurrence advances the schedule'
    assert_nil task.last_error
    assert_equal first.id, task.last_skipped_issue_id
    assert_in_delta Time.current, task.last_skipped_at, 60
    assert_equal 0, last_run.issues_created
    assert_nil last_run.error_messages
    assert_equal "##{task.id} Weekly report: skipped: ##{first.id} is still open", last_run.notes
  end

  def test_skip_mode_resumes_and_clears_the_skip_once_the_previous_issue_is_closed
    task = create_task(if_previous_open: 'skip')
    first = run_due(task)
    run_due(task)
    assert_equal first.id, task.last_skipped_issue_id

    close(first)
    second = run_due(task)
    assert_not_nil second
    assert_nil task.last_skipped_issue_id
    assert_nil task.last_skipped_at
    assert_equal 1, last_run.issues_created
  end

  # --- close_previous -------------------------------------------------------

  def test_close_previous_mode_closes_the_previous_issue_with_a_journal_and_creates_the_new_one
    task = create_task(if_previous_open: 'close_previous', subtasks: [{ 'subject' => 'Child' }])
    first = run_due(task)
    child = task.created_issues.find_by(parent_id: first.id)

    second = run_due(task)
    assert_not_nil second
    assert first.reload.closed?
    assert child.reload.closed?
    assert_equal IssueStatus.where(is_closed: true).sorted.first, first.status
    assert_not_nil first.closed_on
    assert_equal User.find(2), first.journals.last.user
    assert_match(/##{second.id}/, first.journals.last.notes)
    assert_not second.reload.closed?
    assert_nil task.last_error
    assert_nil task.last_skipped_at
    assert_equal 1, last_run.issues_created
    assert_nil last_run.error_messages
  end

  def test_close_previous_mode_prefers_a_closed_status_the_workflow_allows
    task = create_task(if_previous_open: 'close_previous')
    first = run_due(task)
    allowed = first.new_statuses_allowed_to(User.find(2))
    assert allowed.any?(&:is_closed?), 'fixture workflow should allow a closed status'

    run_due(task)
    assert_equal allowed.find(&:is_closed?), first.reload.status
  end

  def test_close_previous_mode_falls_back_to_any_closed_status_without_a_workflow
    WorkflowTransition.delete_all
    task = create_task(if_previous_open: 'close_previous')
    first = run_due(task)
    run_due(task)
    assert first.reload.closed?
    assert_nil task.last_error
  end

  def test_close_previous_failure_is_reported_but_does_not_prevent_the_new_issue
    task = create_task(if_previous_open: 'close_previous')
    first = run_due(task)
    blocker = Issue.create!(project: @project, tracker_id: 1, author_id: 2, subject: 'Blocker')
    IssueRelation.create!(issue_from: blocker, issue_to: first, relation_type: 'blocks')

    second = nil
    assert_difference('Issue.count') { second = run_due(task) }
    assert_not_nil second
    assert_not first.reload.closed?
    assert_match(/Could not close the previous issue ##{first.id}/, task.last_error)
    assert_match(/##{task.id} Weekly report: Could not close/, last_run.error_messages)
    assert_equal 1, last_run.issues_created
  end

  def test_close_previous_mode_leaves_a_closed_previous_issue_alone
    task = create_task(if_previous_open: 'close_previous')
    first = run_due(task)
    close(first)
    journals = first.journals.count

    run_due(task)
    assert_equal journals, first.reload.journals.count
  end

  # --- after_completion -----------------------------------------------------

  def test_after_completion_mode_waits_without_advancing_while_the_previous_issue_is_open
    task = create_task(if_previous_open: 'after_completion')
    first = run_due(task)

    task.update_columns(next_run_date: 1.hour.ago)
    due_at = task.reload.next_run_date
    assert_no_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    task.reload
    assert_equal due_at.to_i, task.next_run_date.to_i, 'the schedule is not advanced'
    assert_equal first.id, task.last_skipped_issue_id
    assert_nil task.last_error
    assert_match(/skipped: ##{first.id} is still open/, last_run.notes)
  end

  def test_after_completion_mode_reschedules_from_the_closing_date
    due = 3.days.ago.change(hour: 10, min: 0, sec: 0, usec: 0)
    task = create_task(if_previous_open: 'after_completion', next_run_date: due)
    first = run_due(task, at: due)
    assert_nil run_due(task, at: due), 'waits while the first issue is open'
    closed_at = 1.day.ago.change(hour: 15, min: 37, sec: 0, usec: 0)
    close(first, closed_at)

    assert_no_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    task.reload
    assert_equal closed_at.change(hour: 10, min: 0) + 1.week, task.next_run_date
    assert_nil task.last_skipped_issue_id
    assert_nil task.last_skipped_at
    assert_match(/##{first.id} was closed, next run rescheduled to/, last_run.notes)
    assert_equal 0, last_run.issues_created
  end

  def test_after_completion_mode_creates_the_next_issue_once_the_interval_after_closing_has_passed
    task = create_task(if_previous_open: 'after_completion')
    first = run_due(task)
    close(first, 8.days.ago)

    second = run_due(task)
    assert_not_nil second
    assert task.next_run_date > Time.current
    assert_nil task.last_skipped_at
  end

  def test_after_completion_mode_uses_updated_on_when_closed_on_is_missing
    task = create_task(if_previous_open: 'after_completion')
    first = run_due(task)
    close(first, 8.days.ago)
    first.update_columns(closed_on: nil, updated_on: 8.days.ago)

    assert_not_nil run_due(task)
  end

  def test_waiting_runs_are_coalesced_in_the_scheduler_log
    task = create_task(if_previous_open: 'after_completion')
    run_due(task)
    task.update_columns(next_run_date: 1.hour.ago)
    PeriodictaskRun.delete_all

    3.times { ScheduledTasksChecker.checktasks! }
    assert_equal 1, PeriodictaskRun.count
    assert_equal 3, last_run.runs_count
    assert_equal 1, last_run.tasks_due
  end

  def test_runs_with_different_notes_or_task_counts_are_not_coalesced
    record = lambda do |tasks_due, notes|
      PeriodictaskRun.record!(source: 'rake', started_at: Time.current, finished_at: Time.current,
                              tasks_due: tasks_due, issues_created: 0, errors: [], notes: notes)
    end
    record.call(1, ['#1 a: skipped: #10 is still open'])
    record.call(1, ['#1 a: skipped: #10 is still open'])
    assert_equal 1, PeriodictaskRun.count
    record.call(1, ['#1 a: skipped: #11 is still open'])
    assert_equal 2, PeriodictaskRun.count
    record.call(2, ['#1 a: skipped: #11 is still open', '#2 b: skipped: #12 is still open'])
    assert_equal 3, PeriodictaskRun.count
    record.call(0, [])
    assert_equal 4, PeriodictaskRun.count
  end

  # --- next_run_date_after_completion ---------------------------------------

  def after_completion_task(attrs = {})
    Periodictask.new({ project: @project, tracker_id: 1, author_id: 2, subject: 'x',
                       interval_number: 1, interval_units: 'day',
                       next_run_date: Time.zone.parse('2026-09-01 10:00') }.merge(attrs))
  end

  def assert_resumes_at(expected, task, closed_at)
    assert_equal Time.zone.parse(expected), task.next_run_date_after_completion(Time.zone.parse(closed_at))
  end

  def test_next_run_after_completion_keeps_the_time_of_day
    task = after_completion_task
    assert_resumes_at '2026-09-08 10:00', task, '2026-09-07 15:37'
    assert_resumes_at '2026-09-08 10:00', task, '2026-09-07 09:00'
  end

  def test_next_run_after_completion_counts_the_interval_from_the_closing_day
    fortnightly = after_completion_task(interval_number: 2, interval_units: 'week')
    assert_resumes_at '2026-09-23 10:00', fortnightly, '2026-09-09 18:00'
    monthly = after_completion_task(interval_number: 1, interval_units: 'month')
    assert_resumes_at '2026-10-30 10:00', monthly, '2026-09-30 08:00'
  end

  def test_next_run_after_completion_follows_selected_weekdays
    task = after_completion_task(interval_units: 'week', weekdays: [1, 3]) # Monday, Wednesday
    assert_resumes_at '2026-09-09 10:00', task, '2026-09-08 12:00' # closed on a Tuesday
    assert_resumes_at '2026-09-14 10:00', task, '2026-09-09 12:00' # closed on a Wednesday
  end

  def test_next_run_after_completion_skips_weekends_for_business_days
    task = after_completion_task(interval_units: 'business_day')
    assert_resumes_at '2026-09-14 10:00', task, '2026-09-11 16:00' # closed on a Friday
  end

  def test_next_run_after_completion_for_the_fourth_thursday_of_the_month
    task = after_completion_task(interval_units: 'month', monthly_mode: 'weekday', weekdays: [4], month_weeks: [4])
    assert_resumes_at '2026-10-22 10:00', task, '2026-09-24 17:00'
    assert_resumes_at '2026-09-24 10:00', task, '2026-09-23 17:00'
  end

  def test_next_run_after_completion_without_a_schedule_anchor_adds_the_interval
    task = after_completion_task(next_run_date: nil, interval_number: 3)
    closed_at = Time.zone.parse('2026-09-07 15:37')
    assert_equal closed_at + 3.days, task.next_run_date_after_completion(closed_at)
  end

  def test_next_run_after_completion_without_a_schedule_anchor_counts_business_days
    task = after_completion_task(next_run_date: nil, interval_units: 'business_day')
    closed_at = Time.zone.parse('2026-09-11 16:00') # Friday
    assert_equal Time.zone.parse('2026-09-14 16:00'), task.next_run_date_after_completion(closed_at)
  end

  def test_next_run_after_completion_uses_the_closing_day_in_the_schedule_time_zone
    task = after_completion_task(next_run_date: Time.zone.parse('2026-09-01 10:00 UTC'))
    late_utc = Time.new(2026, 9, 7, 20, 30, 0, '-05:00') # 2026-09-08 01:30 UTC
    assert_equal Time.zone.parse('2026-09-09 10:00 UTC'), task.next_run_date_after_completion(late_utc)
  end
end
