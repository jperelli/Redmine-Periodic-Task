require File.dirname(__FILE__) + '/../test_helper'

class PeriodictasksTest < ActiveSupport::TestCase
  fixtures :projects, :users, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :enabled_modules, :roles, :members, :member_roles

  def setup
    @project = Project.find(1)
    EnabledModule.create!(project: @project, name: 'periodictask')
  end

  def test_create_valid_periodictask
    task = Periodictask.new(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Valid task',
      interval_number: 1,
      interval_units: 'month'
    )
    assert task.valid?
    assert task.save
  end

  def test_interval_number_required
    task = Periodictask.new(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Task',
      interval_units: 'month'
    )
    task.interval_number = nil # override after_initialize default
    assert_not task.valid?
    assert task.errors[:interval_number].any?
  end

  def test_interval_number_must_be_positive
    task = Periodictask.new(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Task',
      interval_number: -1,
      interval_units: 'month'
    )
    assert_not task.valid?
  end

  def test_interval_number_must_be_integer
    task = Periodictask.new(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Task',
      interval_number: 1.5,
      interval_units: 'month'
    )
    assert_not task.valid?
  end

  def test_interval_units_required
    task = Periodictask.new(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Task',
      interval_number: 1
    )
    task.interval_units = nil # override after_initialize default
    assert_not task.valid?
    assert task.errors[:interval_units].any?
  end

  def test_generate_issue
    task = Periodictask.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      assigned_to_id: 2,
      subject: 'Generate issue test',
      interval_number: 1,
      interval_units: 'month',
      next_run_date: 1.month.from_now
    )
    issue = task.generate_issue
    assert_not_nil issue
    assert_equal 'Generate issue test', issue.subject
    assert_equal @project.id, issue.project_id
    assert_equal 1, issue.tracker_id
    assert_equal 2, issue.assigned_to_id
  end

  def test_generate_issue_with_start_date
    task = Periodictask.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Start date test',
      interval_number: 1,
      interval_units: 'month',
      set_start_date: true,
      next_run_date: 1.month.from_now
    )
    issue = task.generate_issue
    assert_not_nil issue.start_date
  end

  def test_generate_issue_with_due_date
    task = Periodictask.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Due date test',
      interval_number: 1,
      interval_units: 'month',
      due_date_number: 7,
      due_date_units: 'day',
      next_run_date: 1.month.from_now
    )
    issue = task.generate_issue
    assert_not_nil issue.due_date
  end

  def test_macro_substitution_in_subject
    now = Time.utc(2026, 3, 15, 10, 0, 0)
    task = Periodictask.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Monthly report **MONTH**/**YEAR**',
      interval_number: 1,
      interval_units: 'month',
      next_run_date: now
    )
    issue = task.generate_issue(now)
    assert_equal 'Monthly report 03/2026', issue.subject
  end

  def test_macro_substitution_day_and_week
    now = Time.utc(2026, 6, 15, 10, 0, 0)
    task = Periodictask.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Report **DAY** week **WEEK**',
      interval_number: 1,
      interval_units: 'month',
      next_run_date: now
    )
    issue = task.generate_issue(now)
    assert_equal "Report #{now.strftime('%d')} week #{now.strftime('%W')}", issue.subject
  end

  def test_get_next_run_date_monthly
    scheduled = Time.utc(2026, 1, 1, 10, 0, 0)
    now = scheduled + 1.hour # simulate running after scheduled time
    task = Periodictask.new(
      interval_number: 1,
      interval_units: 'month',
      next_run_date: scheduled
    )
    next_date = task.get_next_run_date(now)
    assert next_date > now
    assert_equal 2, next_date.month
  end

  def test_get_next_run_date_weekly
    scheduled = Time.utc(2026, 1, 1, 10, 0, 0)
    now = scheduled + 1.hour
    task = Periodictask.new(
      interval_number: 1,
      interval_units: 'week',
      next_run_date: scheduled
    )
    next_date = task.get_next_run_date(now)
    assert next_date > now
    assert_equal scheduled + 1.week, next_date
  end

  def test_get_next_run_date_daily
    scheduled = Time.utc(2026, 1, 1, 10, 0, 0)
    now = scheduled + 1.hour
    task = Periodictask.new(
      interval_number: 1,
      interval_units: 'day',
      next_run_date: scheduled
    )
    next_date = task.get_next_run_date(now)
    assert next_date > now
    assert_equal scheduled + 1.day, next_date
  end

  def test_get_next_run_date_yearly
    scheduled = Time.utc(2026, 1, 1, 10, 0, 0)
    now = scheduled + 1.hour
    task = Periodictask.new(
      interval_number: 1,
      interval_units: 'year',
      next_run_date: scheduled
    )
    next_date = task.get_next_run_date(now)
    assert next_date > now
    assert_equal 2027, next_date.year
  end

  def test_belongs_to_project
    task = Periodictask.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Association test',
      interval_number: 1,
      interval_units: 'month'
    )
    assert_equal @project, task.project
    assert_equal @project.id, task.project_id
  end

  def test_default_values_on_new_record
    task = Periodictask.new
    assert_equal 1, task.interval_number
    assert_not_nil task.interval_units
  end

  def test_scheduled_tasks_checker
    task = Periodictask.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      assigned_to_id: 2,
      subject: 'Checker test',
      interval_number: 1,
      interval_units: 'month',
      next_run_date: 1.day.ago
    )

    assert_difference('Issue.count') do
      ScheduledTasksChecker.checktasks!
    end

    task.reload
    assert task.next_run_date > Time.current
    assert_nil task.last_error
  end

  def test_generate_issue_with_parent_id
    # Create a parent issue first
    parent_issue = Issue.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Parent issue',
      status_id: 1,
      priority_id: IssuePriority.first.id
    )

    task = Periodictask.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Child periodic task',
      interval_number: 1,
      interval_units: 'month',
      parent_id: parent_issue.id,
      next_run_date: 1.month.from_now
    )
    issue = task.generate_issue
    assert_not_nil issue
    assert_equal parent_issue.id, issue.parent_id
    assert_equal 'Child periodic task', issue.subject
  end

  def test_generate_issue_without_parent_id
    task = Periodictask.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'No parent task',
      interval_number: 1,
      interval_units: 'month',
      next_run_date: 1.month.from_now
    )
    issue = task.generate_issue
    assert_not_nil issue
    assert_nil issue.parent_id
  end

  def test_periodictask_stores_parent_id
    task = Periodictask.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Store parent test',
      interval_number: 1,
      interval_units: 'month',
      parent_id: 42
    )
    task.reload
    assert_equal 42, task.parent_id
  end

  def test_macro_quarter_q1
    now = Time.utc(2026, 2, 15, 10, 0, 0)
    task = Periodictask.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Q**QUARTER** report',
      interval_number: 1,
      interval_units: 'month',
      next_run_date: now
    )
    issue = task.generate_issue(now)
    assert_equal 'Q1 report', issue.subject
  end

  def test_macro_quarter_q2
    now = Time.utc(2026, 5, 1, 10, 0, 0)
    task = Periodictask.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Q**QUARTER**',
      interval_number: 1,
      interval_units: 'month',
      next_run_date: now
    )
    issue = task.generate_issue(now)
    assert_equal 'Q2', issue.subject
  end

  def test_macro_quarter_q3
    now = Time.utc(2026, 9, 30, 10, 0, 0)
    task = Periodictask.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Q**QUARTER**',
      interval_number: 1,
      interval_units: 'month',
      next_run_date: now
    )
    issue = task.generate_issue(now)
    assert_equal 'Q3', issue.subject
  end

  def test_macro_quarter_q4
    now = Time.utc(2026, 12, 31, 10, 0, 0)
    task = Periodictask.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Q**QUARTER**',
      interval_number: 1,
      interval_units: 'month',
      next_run_date: now
    )
    issue = task.generate_issue(now)
    assert_equal 'Q4', issue.subject
  end

  def test_macro_weekiso
    now = Time.utc(2026, 1, 5, 10, 0, 0) # Monday of ISO week 02
    task = Periodictask.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Week **WEEKISO**',
      interval_number: 1,
      interval_units: 'week',
      next_run_date: now
    )
    issue = task.generate_issue(now)
    assert_equal "Week #{now.strftime('%V')}", issue.subject
  end

  def test_macro_previous_month_on_march_1st
    now = Time.utc(2026, 3, 1, 10, 0, 0)
    task = Periodictask.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Report **PREVIOUS_MONTH**',
      interval_number: 1,
      interval_units: 'month',
      next_run_date: now
    )
    issue = task.generate_issue(now)
    assert_equal 'Report 02', issue.subject
  end

  def test_macro_previous_monthname_on_march_1st
    now = Time.utc(2026, 3, 1, 10, 0, 0)
    task = Periodictask.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Report **PREVIOUS_MONTHNAME**',
      interval_number: 1,
      interval_units: 'month',
      next_run_date: now
    )
    issue = task.generate_issue(now)
    assert_equal 'Report February', issue.subject
  end

  def test_macro_previous_month_on_january_1st
    now = Time.utc(2026, 1, 1, 10, 0, 0)
    task = Periodictask.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Report **PREVIOUS_MONTH**',
      interval_number: 1,
      interval_units: 'month',
      next_run_date: now
    )
    issue = task.generate_issue(now)
    assert_equal 'Report 12', issue.subject
  end

  def test_macro_substitution_in_description
    now = Time.utc(2026, 7, 20, 10, 0, 0)
    task = Periodictask.create!(
      project: @project,
      tracker_id: 1,
      author_id: 1,
      subject: 'Test',
      description: 'Q**QUARTER** W**WEEKISO** **PREVIOUS_MONTH**',
      interval_number: 1,
      interval_units: 'month',
      next_run_date: now
    )
    issue = task.generate_issue(now)
    assert_equal "Q3 W#{now.strftime('%V')} 06", issue.description
  end
end
