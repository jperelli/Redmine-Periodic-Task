require "#{File.dirname(__FILE__)}/../test_helper"

class PeriodictaskRunTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issue_categories

  def setup
    Periodictask.delete_all
    PeriodictaskRun.delete_all
  end

  def record(source: 'web', tasks_due: 0, issues_created: 0, errors: [], at: Time.current)
    PeriodictaskRun.record!(source: source, started_at: at, finished_at: at + 0.25,
                            tasks_due: tasks_due, issues_created: issues_created, errors: errors)
  end

  def test_records_run_details
    run = record(source: 'endpoint', tasks_due: 2, issues_created: 1, errors: ['#1 foo: boom'])
    assert_equal 'endpoint', run.source
    assert_equal 2, run.tasks_due
    assert_equal 1, run.issues_created
    assert_equal 250, run.duration_ms
    assert_equal '#1 foo: boom', run.error_messages
    assert_equal 1, run.runs_count
  end

  def test_consecutive_noop_runs_from_same_source_are_coalesced
    t = Time.current.change(usec: 0)
    first = record(at: t)
    record(at: t + 5.minutes)
    record(at: t + 10.minutes)
    assert_equal 1, PeriodictaskRun.count
    first.reload
    assert_equal 3, first.runs_count
    assert_equal t, first.started_at
    assert_equal t + 10.minutes, first.last_run_at
  end

  def test_noop_runs_are_not_coalesced_across_sources_or_after_activity
    record(source: 'web')
    record(source: 'rake')
    assert_equal 2, PeriodictaskRun.count
    record(source: 'rake', tasks_due: 1, issues_created: 1)
    record(source: 'rake')
    assert_equal 4, PeriodictaskRun.count
  end

  def test_runs_with_errors_are_never_coalesced
    record(errors: ['x'])
    record(errors: ['x'])
    assert_equal 2, PeriodictaskRun.count
  end

  def test_keeps_only_last_runs
    t = Time.current
    (PeriodictaskRun::KEEP + 5).times { |i| record(tasks_due: 1, issues_created: 1, at: t + i.minutes) }
    assert_equal PeriodictaskRun::KEEP, PeriodictaskRun.count
    assert_equal t.change(usec: 0) + 54.minutes, PeriodictaskRun.recent.first.started_at.change(usec: 0)
    assert_equal t.change(usec: 0) + 5.minutes, PeriodictaskRun.recent.last.started_at.change(usec: 0)
  end

  def test_checker_records_run_with_source_and_errors
    Periodictask.create!(project_id: 1, tracker_id: 1, author_id: 2, assigned_to_id: 2,
                         subject: 'Due task', interval_number: 1, interval_units: 'day',
                         next_run_date: 1.hour.ago)
    missing = Periodictask.create!(project_id: 1, tracker_id: 1, author_id: 2, assigned_to_id: 2,
                                   subject: 'Orphan', interval_number: 1, interval_units: 'day',
                                   next_run_date: 1.hour.ago)
    missing.update_column(:project_id, 9999)

    assert_equal 2, ScheduledTasksChecker.checktasks!(source: 'manual')
    run = PeriodictaskRun.recent.first
    assert_equal 'manual', run.source
    assert_equal 2, run.tasks_due
    assert_equal 1, run.issues_created
    assert_match(/##{missing.id} Orphan: Project is missing or closed/, run.error_messages)
  end

  def test_checker_defaults_to_rake_source_and_records_noop
    assert_equal 0, ScheduledTasksChecker.checktasks!
    run = PeriodictaskRun.recent.first
    assert_equal 'rake', run.source
    assert run.noop?
  end
end
