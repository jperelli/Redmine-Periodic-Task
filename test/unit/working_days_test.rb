require "#{File.dirname(__FILE__)}/../test_helper"

# Business-day intervals and the weekend_adjustment option both follow
# Redmine's non-working days setting (Administration > Settings > Issue
# tracking), not a hard-coded Saturday/Sunday weekend.
class WorkingDaysTest < ActiveSupport::TestCase
  fixtures :projects, :users, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :enabled_modules, :roles, :members, :member_roles

  FRI_SAT = %w[5 6].freeze

  def setup
    @project = Project.find(1)
    EnabledModule.create!(project: @project, name: 'periodictask')
  end

  # ---- business_day interval ----

  def test_business_day_skips_default_weekend_and_keeps_time
    anchor = Time.utc(2026, 8, 7, 10, 30, 0) # Friday
    task = business_days(anchor)

    assert_equal Time.utc(2026, 8, 10, 10, 30, 0), task.get_next_run_date(anchor + 5.minutes) # Monday
  end

  def test_business_day_uses_configured_non_working_days
    anchor = Time.utc(2026, 8, 6, 10, 0, 0) # Thursday
    task = business_days(anchor)

    with_settings non_working_week_days: FRI_SAT do
      assert_equal Time.utc(2026, 8, 9, 10, 0, 0), task.get_next_run_date(anchor + 5.minutes) # Sunday
    end
  end

  def test_business_day_counts_only_working_days_when_several
    anchor = Time.utc(2026, 8, 6, 10, 0, 0) # Thursday
    task = business_days(anchor, 3)

    assert_equal Time.utc(2026, 8, 11, 10, 0, 0), task.get_next_run_date(anchor + 5.minutes) # Tuesday
    with_settings non_working_week_days: %w[7] do
      assert_equal Time.utc(2026, 8, 10, 10, 0, 0), task.get_next_run_date(anchor + 5.minutes) # Monday
    end
  end

  def test_business_day_without_non_working_days_behaves_like_days
    anchor = Time.utc(2026, 8, 7, 10, 0, 0) # Friday

    with_settings non_working_week_days: [] do
      assert_equal Time.utc(2026, 8, 8, 10, 0, 0), business_days(anchor).get_next_run_date(anchor + 5.minutes)
    end
  end

  def test_business_day_after_downtime_skips_to_next_future_working_day
    anchor = Time.utc(2026, 8, 3, 10, 0, 0) # Monday
    task = business_days(anchor)

    assert_equal Time.utc(2026, 8, 24, 10, 0, 0), task.get_next_run_date(Time.utc(2026, 8, 22, 8, 0, 0)) # Sat -> Mon
  end

  def test_business_day_preserves_time_zone
    with_time_zone 'Tokyo' do
      anchor = Time.zone.local(2026, 8, 7, 10, 0, 0) # Friday
      next_date = business_days(anchor).get_next_run_date(anchor + 5.minutes)

      assert_equal Time.zone.local(2026, 8, 10, 10, 0, 0), next_date
      assert_equal 10, next_date.hour
      assert_equal 1, next_date.utc.hour
    end
  end

  def test_business_day_due_date_uses_configured_non_working_days
    task = valid_task(interval_units: 'day', due_date_number: 2, due_date_units: 'business_day', set_start_date: true)

    with_settings non_working_week_days: FRI_SAT do
      issue = task.generate_issue(Time.utc(2026, 8, 6, 10, 0, 0)) # Thursday
      assert_equal Date.new(2026, 8, 10), issue.due_date # Sun, Mon
    end
    issue = task.generate_issue(Time.utc(2026, 8, 6, 10, 0, 0))
    assert_equal Date.new(2026, 8, 10), issue.due_date # Fri, Mon
  end

  # ---- weekend_adjustment ----

  def test_weekend_adjustment_defaults_to_none_and_rejects_unknown_values
    assert_equal 'none', Periodictask.new.weekend_adjustment
    assert_equal 'none', Periodictask.new(weekend_adjustment: 'bogus').weekend_adjustment
    assert_equal 'next_working_day', Periodictask.new(weekend_adjustment: 'next_working_day').weekend_adjustment
    assert_not Periodictask.new.weekend_adjusted?
    assert Periodictask.new(weekend_adjustment: 'previous_working_day').weekend_adjusted?
  end

  def test_records_with_an_unknown_stored_value_behave_as_before
    task = valid_task(next_run_date: Time.utc(2026, 8, 1, 10, 0, 0))
    task.save!
    task.update_columns(weekend_adjustment: 'skip')
    task.reload

    assert_equal 'none', task.weekend_adjustment
    assert_equal task.next_run_date, task.effective_next_run_date
  end

  def test_monthly_occurrence_on_saturday_moves_forward_or_backward_keeping_time
    saturday = Time.utc(2026, 8, 1, 10, 30, 0)

    assert_equal saturday, monthly(saturday, 'none').effective_next_run_date
    assert_equal Time.utc(2026, 8, 3, 10, 30, 0), monthly(saturday, 'next_working_day').effective_next_run_date
    assert_equal Time.utc(2026, 7, 31, 10, 30, 0), monthly(saturday, 'previous_working_day').effective_next_run_date
  end

  def test_working_day_occurrence_is_not_moved
    tuesday = Time.utc(2026, 9, 1, 10, 0, 0)

    assert_equal tuesday, monthly(tuesday, 'next_working_day').effective_next_run_date
    assert_equal tuesday, monthly(tuesday, 'previous_working_day').effective_next_run_date
  end

  def test_adjustment_uses_configured_non_working_days
    friday = Time.utc(2026, 8, 7, 10, 0, 0)

    with_settings non_working_week_days: FRI_SAT do
      assert_equal Time.utc(2026, 8, 9, 10, 0, 0), monthly(friday, 'next_working_day').effective_next_run_date
      assert_equal Time.utc(2026, 8, 6, 10, 0, 0), monthly(friday, 'previous_working_day').effective_next_run_date
    end
    assert_equal friday, monthly(friday, 'next_working_day').effective_next_run_date
  end

  def test_adjustment_skips_consecutive_non_working_days
    saturday = Time.utc(2026, 8, 1, 10, 0, 0)

    with_settings non_working_week_days: %w[5 6 7 1] do
      assert_equal Time.utc(2026, 8, 4, 10, 0, 0), monthly(saturday, 'next_working_day').effective_next_run_date
      assert_equal Time.utc(2026, 7, 30, 10, 0, 0), monthly(saturday, 'previous_working_day').effective_next_run_date
    end
  end

  def test_adjustment_preserves_time_zone
    with_time_zone 'Tokyo' do
      saturday = Time.zone.local(2026, 8, 1, 10, 0, 0)
      moved = monthly(saturday, 'next_working_day').effective_next_run_date

      assert_equal Time.zone.local(2026, 8, 3, 10, 0, 0), moved
      assert_equal 10, moved.hour
      assert_equal 1, moved.utc.hour
    end
  end

  def test_recurrence_anchor_stays_on_the_unadjusted_date
    saturday = Time.utc(2026, 8, 1, 10, 0, 0)
    task = monthly(saturday, 'next_working_day')

    # Moved to Mon Aug 3; the next occurrence is still the 1st, not the 3rd.
    assert_equal Time.utc(2026, 9, 1, 10, 0, 0), task.get_next_run_date(saturday + 5.minutes)
    task = monthly(saturday, 'previous_working_day')
    assert_equal Time.utc(2026, 9, 1, 10, 0, 0), task.get_next_run_date(saturday + 5.minutes)
  end

  def test_yearly_occurrence_on_sunday_is_moved
    sunday = Time.utc(2027, 8, 1, 10, 0, 0)
    task = valid_task(interval_units: 'year', weekend_adjustment: 'next_working_day', next_run_date: sunday)

    assert_equal Time.utc(2027, 8, 2, 10, 0, 0), task.effective_next_run_date
    assert_equal Time.utc(2028, 8, 1, 10, 0, 0), task.get_next_run_date(sunday + 5.minutes) # Tuesday, unadjusted
    task.weekend_adjustment = 'previous_working_day'
    assert_equal Time.utc(2027, 7, 30, 10, 0, 0), task.effective_next_run_date
  end

  def test_weekly_on_selected_weekday_is_moved
    saturday = Time.utc(2026, 8, 1, 10, 0, 0)
    task = valid_task(interval_units: 'week', weekdays: [6], weekend_adjustment: 'previous_working_day',
                      next_run_date: saturday)

    assert_equal Time.utc(2026, 7, 31, 10, 0, 0), task.effective_next_run_date
    assert_equal Time.utc(2026, 8, 8, 10, 0, 0), task.get_next_run_date(saturday + 5.minutes)
  end

  def test_due_by_uses_the_moved_run_time
    saturday = Time.utc(2026, 8, 1, 10, 0, 0)
    task = monthly(saturday, 'previous_working_day')

    assert_not task.due_by?(Time.utc(2026, 7, 31, 9, 59, 0))
    assert task.due_by?(Time.utc(2026, 7, 31, 10, 0, 0))
    assert_not monthly(saturday, 'next_working_day').due_by?(Time.utc(2026, 8, 2, 12, 0, 0))
    assert monthly(saturday, 'next_working_day').due_by?(Time.utc(2026, 8, 3, 10, 0, 0))
    assert_not Periodictask.new(weekend_adjustment: 'previous_working_day').due_by?(saturday)
  end

  def test_weekend_adjustment_is_kept_for_every_unit
    %w[day business_day week month year].each do |unit|
      task = valid_task(interval_units: unit, weekend_adjustment: 'next_working_day')
      assert task.save, task.errors.full_messages.join(', ')
      assert_equal 'next_working_day', task.reload.weekend_adjustment
    end
  end

  # ---- scheduler integration ----

  def test_checker_runs_early_on_previous_working_day_and_advances_from_the_unadjusted_date
    task = valid_task(interval_units: 'month', weekend_adjustment: 'previous_working_day',
                      next_run_date: Time.utc(2026, 8, 1, 10, 0, 0)) # Saturday
    task.save!

    travel_to Time.utc(2026, 7, 31, 9, 55, 0) do # Friday, too early
      assert_no_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    end
    travel_to Time.utc(2026, 7, 31, 10, 3, 0) do # Friday 10:00 run
      assert_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    end
    assert_equal Time.utc(2026, 9, 1, 10, 0, 0), task.reload.next_run_date # Tuesday, still the 1st

    travel_to Time.utc(2026, 8, 1, 12, 0, 0) do # the unadjusted Saturday: nothing to do again
      assert_no_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    end
    travel_to Time.utc(2026, 9, 1, 10, 2, 0) do
      assert_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    end
    assert_equal Time.utc(2026, 10, 1, 10, 0, 0), task.reload.next_run_date
    assert_equal 2, task.created_issues.count
  end

  def test_checker_runs_late_on_next_working_day_without_double_adjustment
    task = valid_task(interval_units: 'month', weekend_adjustment: 'next_working_day',
                      next_run_date: Time.utc(2026, 8, 1, 10, 0, 0)) # Saturday
    task.save!

    travel_to Time.utc(2026, 8, 1, 10, 5, 0) do # Saturday: waits for Monday
      assert_no_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    end
    travel_to Time.utc(2026, 8, 3, 10, 5, 0) do # Monday 10:00 run
      assert_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    end
    assert_equal Time.utc(2026, 9, 1, 10, 0, 0), task.reload.next_run_date
    assert_equal task.next_run_date, task.effective_next_run_date

    travel_to Time.utc(2026, 9, 1, 10, 5, 0) do
      assert_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    end
    assert_equal Time.utc(2026, 10, 1, 10, 0, 0), task.reload.next_run_date
  end

  def test_checker_moves_daily_runs_over_a_weekend_into_one_working_day_run
    task = valid_task(interval_units: 'day', weekend_adjustment: 'next_working_day',
                      next_run_date: Time.utc(2026, 8, 1, 10, 0, 0)) # Saturday
    task.save!

    travel_to Time.utc(2026, 8, 2, 10, 5, 0) do # Sunday
      assert_no_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    end
    travel_to Time.utc(2026, 8, 3, 10, 5, 0) do # Monday
      assert_difference('Issue.count', 1) { ScheduledTasksChecker.checktasks! }
    end
    assert_equal Time.utc(2026, 8, 4, 10, 0, 0), task.reload.next_run_date
  end

  def test_checker_respects_configured_non_working_days
    task = valid_task(interval_units: 'month', weekend_adjustment: 'next_working_day',
                      next_run_date: Time.utc(2026, 8, 7, 10, 0, 0)) # Friday
    task.save!

    with_settings non_working_week_days: FRI_SAT do
      travel_to Time.utc(2026, 8, 7, 10, 5, 0) do
        assert_no_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
      end
      travel_to Time.utc(2026, 8, 9, 10, 5, 0) do # Sunday is a working day here
        assert_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
      end
    end
    assert_equal Time.utc(2026, 9, 7, 10, 0, 0), task.reload.next_run_date
  end

  private

  def business_days(anchor, interval_number = 1)
    Periodictask.new(interval_number: interval_number, interval_units: 'business_day', next_run_date: anchor)
  end

  def monthly(anchor, weekend_adjustment)
    Periodictask.new(interval_number: 1, interval_units: 'month', weekend_adjustment: weekend_adjustment,
                     next_run_date: anchor)
  end

  def valid_task(attrs = {})
    Periodictask.new({ project: @project, tracker_id: 1, author_id: 1, assigned_to_id: 2,
                       subject: 'Working days', interval_number: 1 }.merge(attrs))
  end

  def with_time_zone(name)
    original = Time.zone
    Time.zone = name
    yield
  ensure
    Time.zone = original
  end
end
