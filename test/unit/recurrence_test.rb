require "#{File.dirname(__FILE__)}/../test_helper"

# Recurrence rules for Periodictask#get_next_run_date: weekly on selected
# weekdays and monthly on selected ordinal weekdays (e.g. 1st and 3rd Monday).
# https://github.com/jperelli/Redmine-Periodic-Task/issues/50
class RecurrenceTest < ActiveSupport::TestCase
  fixtures :projects, :users, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :enabled_modules, :roles, :members, :member_roles

  MON = 1
  WED = 3
  SUN = 0

  def setup
    @project = Project.find(1)
    EnabledModule.create!(project: @project, name: 'periodictask')
  end

  # ---- weekly ----

  def test_weekly_picks_next_selected_weekday_in_same_week
    anchor = Time.utc(2026, 1, 5, 10, 0, 0) # Monday
    task = weekly(anchor, [MON, WED])

    assert_equal Time.utc(2026, 1, 7, 10, 0, 0), task.get_next_run_date(anchor + 5.minutes)
  end

  def test_weekly_wraps_to_first_selected_weekday_of_next_week
    anchor = Time.utc(2026, 1, 7, 10, 0, 0) # Wednesday
    task = weekly(anchor, [MON, WED])

    assert_equal Time.utc(2026, 1, 12, 10, 0, 0), task.get_next_run_date(anchor + 5.minutes)
  end

  def test_weekly_anchor_not_on_a_selected_weekday_moves_to_next_selected_one
    anchor = Time.utc(2026, 1, 6, 10, 0, 0) # Tuesday
    task = weekly(anchor, [MON, WED])

    assert_equal Time.utc(2026, 1, 7, 10, 0, 0), task.get_next_run_date(anchor + 5.minutes)
  end

  def test_weekly_every_two_weeks_skips_the_week_in_between
    with_settings start_of_week: '1' do
      anchor = Time.utc(2026, 1, 7, 10, 0, 0) # Wednesday, week of Jan 5
      task = weekly(anchor, [MON, WED], 2)

      assert_equal Time.utc(2026, 1, 19, 10, 0, 0), task.get_next_run_date(anchor + 5.minutes)
    end
  end

  def test_weekly_every_two_weeks_uses_configured_start_of_week
    anchor = Time.utc(2026, 1, 4, 10, 0, 0) # Sunday

    with_settings start_of_week: '7' do
      # Sunday-first week: Sun Jan 4 and Mon Jan 5 are in the same week
      assert_equal Time.utc(2026, 1, 5, 10, 0, 0), weekly(anchor, [SUN, MON], 2).get_next_run_date(anchor + 1.minute)
    end
    with_settings start_of_week: '1' do
      # Monday-first week: Sun Jan 4 closes the week of Dec 29, next eligible week starts Jan 12
      assert_equal Time.utc(2026, 1, 12, 10, 0, 0), weekly(anchor, [SUN, MON], 2).get_next_run_date(anchor + 1.minute)
    end
  end

  def test_weekly_blank_next_run_date_runs_today_when_today_is_selected
    now = Time.utc(2026, 1, 5, 10, 0, 0) # Monday
    task = weekly(nil, [MON, WED])

    assert_equal now, task.get_next_run_date(now)
  end

  def test_weekly_blank_next_run_date_moves_to_next_selected_weekday
    now = Time.utc(2026, 1, 5, 10, 0, 0) # Monday
    task = weekly(nil, [WED])

    assert_equal Time.utc(2026, 1, 7, 10, 0, 0), task.get_next_run_date(now)
  end

  def test_weekly_delayed_execution_keeps_scheduled_time
    anchor = Time.utc(2026, 1, 5, 10, 0, 0)
    task = weekly(anchor, [MON, WED])

    assert_equal Time.utc(2026, 1, 7, 10, 0, 0), task.get_next_run_date(anchor + 3.hours + 17.minutes)
  end

  def test_weekly_after_downtime_skips_to_next_future_occurrence
    anchor = Time.utc(2026, 1, 5, 10, 0, 0)
    task = weekly(anchor, [MON, WED])
    now = Time.utc(2026, 2, 3, 15, 0, 0) # Tuesday, four weeks later

    assert_equal Time.utc(2026, 2, 4, 10, 0, 0), task.get_next_run_date(now)
  end

  def test_weekly_preserves_local_time_across_dst_change
    with_time_zone 'Paris' do
      anchor = Time.zone.local(2026, 3, 23, 9, 0, 0) # Monday, CET
      task = weekly(anchor, [MON])
      next_date = task.get_next_run_date(Time.zone.local(2026, 3, 28, 12, 0, 0))

      assert_equal Time.zone.local(2026, 3, 30, 9, 0, 0), next_date # CEST
      assert_equal 9, next_date.hour
      assert_equal 7, next_date.utc.hour
    end
  end

  def test_weekly_without_weekdays_keeps_plain_interval_behaviour
    anchor = Time.utc(2026, 1, 6, 10, 0, 0)
    task = weekly(anchor, [])

    assert_equal anchor + 1.week, task.get_next_run_date(anchor + 5.minutes)
  end

  # ---- monthly on weekdays ----

  def test_monthly_weekday_applies_all_ordinal_weekday_combinations
    anchor = Time.utc(2026, 1, 1, 10, 0, 0) # Thursday
    task = monthly_weekdays(anchor, [1, 3], [MON, WED])
    # Jan 2026: Mondays 5,12,19,26 / Wednesdays 7,14,21,28 ; Feb 2026: first Monday is the 2nd
    expected = [5, 7, 19, 21].map { |d| Time.utc(2026, 1, d, 10, 0, 0) } << Time.utc(2026, 2, 2, 10, 0, 0)

    expected.each do |date|
      assert_equal date, task.get_next_run_date(task.next_run_date + 5.minutes)
      task.next_run_date = date
    end
  end

  def test_monthly_weekday_every_two_months_skips_the_month_in_between
    anchor = Time.utc(2026, 1, 21, 10, 0, 0)
    task = monthly_weekdays(anchor, [1, 3], [MON, WED], 2)

    assert_equal Time.utc(2026, 3, 2, 10, 0, 0), task.get_next_run_date(anchor + 5.minutes)
  end

  def test_monthly_weekday_missing_fifth_falls_back_to_last_occurrence
    anchor = Time.utc(2026, 2, 1, 10, 0, 0)
    task = monthly_weekdays(anchor, [5], [MON])

    assert_equal Time.utc(2026, 2, 23, 10, 0, 0), task.get_next_run_date(anchor + 5.minutes)
  end

  def test_monthly_weekday_deduplicates_fourth_and_fifth_collision
    anchor = Time.utc(2026, 2, 1, 10, 0, 0)
    task = monthly_weekdays(anchor, [4, 5], [MON])

    feb = task.get_next_run_date(anchor + 5.minutes)
    assert_equal Time.utc(2026, 2, 23, 10, 0, 0), feb # 4th and 5th both resolve to the 23rd
    task.next_run_date = feb
    mar4 = task.get_next_run_date(feb + 5.minutes)
    assert_equal Time.utc(2026, 3, 23, 10, 0, 0), mar4
    task.next_run_date = mar4
    assert_equal Time.utc(2026, 3, 30, 10, 0, 0), task.get_next_run_date(mar4 + 5.minutes)
  end

  def test_monthly_weekday_blank_next_run_date_runs_today_when_today_matches
    now = Time.utc(2026, 1, 5, 10, 0, 0) # first Monday
    task = monthly_weekdays(nil, [1], [MON])

    assert_equal now, task.get_next_run_date(now)
  end

  def test_monthly_weekday_blank_next_run_date_moves_to_next_matching_day
    now = Time.utc(2026, 1, 6, 10, 0, 0) # Tuesday after the first Monday
    task = monthly_weekdays(nil, [1], [MON])

    assert_equal Time.utc(2026, 2, 2, 10, 0, 0), task.get_next_run_date(now)
  end

  def test_monthly_weekday_delayed_execution_keeps_scheduled_time
    anchor = Time.utc(2026, 1, 5, 10, 0, 0)
    task = monthly_weekdays(anchor, [1, 3], [MON, WED])

    assert_equal Time.utc(2026, 1, 7, 10, 0, 0), task.get_next_run_date(anchor + 47.minutes)
  end

  def test_monthly_weekday_after_downtime_skips_to_next_future_occurrence
    anchor = Time.utc(2026, 1, 5, 10, 0, 0)
    task = monthly_weekdays(anchor, [1], [MON])

    assert_equal Time.utc(2026, 5, 4, 10, 0, 0), task.get_next_run_date(Time.utc(2026, 4, 20, 8, 0, 0))
  end

  def test_monthly_weekday_preserves_time_zone
    with_time_zone 'Tokyo' do
      anchor = Time.zone.local(2026, 1, 5, 10, 0, 0)
      task = monthly_weekdays(anchor, [3], [WED])
      next_date = task.get_next_run_date(anchor + 20.minutes)

      assert_equal Time.zone.local(2026, 1, 21, 10, 0, 0), next_date
      assert_equal 10, next_date.hour
      assert_equal 1, next_date.utc.hour
    end
  end

  def test_monthly_day_of_month_mode_ignores_weekday_selection
    anchor = Time.utc(2026, 1, 15, 10, 0, 0)
    task = monthly_weekdays(anchor, [1], [MON])
    task.monthly_mode = 'day_of_month'

    assert_equal Time.utc(2026, 2, 15, 10, 0, 0), task.get_next_run_date(anchor + 5.minutes)
  end

  # ---- attribute normalization and validation ----

  def test_weekdays_are_normalized_from_checkbox_values
    task = Periodictask.new(weekdays: ['', '3', '1', '3', '9', 'x'])
    assert_equal [1, 3], task.weekdays
  end

  def test_month_weeks_are_normalized_from_checkbox_values
    task = Periodictask.new(month_weeks: ['', '5', '1', '0', '6'])
    assert_equal [1, 5], task.month_weeks
  end

  def test_monthly_mode_defaults_to_day_of_month
    assert_equal 'day_of_month', Periodictask.new.monthly_mode
    assert_equal 'day_of_month', Periodictask.new(monthly_mode: 'bogus').monthly_mode
    assert_equal 'weekday', Periodictask.new(monthly_mode: 'weekday').monthly_mode
  end

  def test_monthly_weekday_mode_requires_ordinals_and_weekdays
    task = valid_task(interval_units: 'month', monthly_mode: 'weekday', month_weeks: [1], weekdays: [])
    assert_not task.valid?
    assert_includes task.errors.full_messages, I18n.t(:error_recurrence_weekdays_blank)

    task = valid_task(interval_units: 'month', monthly_mode: 'weekday', month_weeks: [], weekdays: [MON])
    assert_not task.valid?
    assert_includes task.errors.full_messages, I18n.t(:error_recurrence_month_weeks_blank)

    task = valid_task(interval_units: 'month', monthly_mode: 'weekday', month_weeks: [1], weekdays: [MON])
    assert task.valid?
  end

  def test_recurrence_options_irrelevant_to_the_unit_are_cleared_on_save
    task = valid_task(interval_units: 'day', monthly_mode: 'weekday', month_weeks: [1], weekdays: [MON])
    assert task.save
    task.reload
    assert_equal [], task.weekdays
    assert_equal [], task.month_weeks
    assert_equal 'day_of_month', task.monthly_mode

    task = valid_task(interval_units: 'week', monthly_mode: 'weekday', month_weeks: [1], weekdays: [MON])
    assert task.save
    task.reload
    assert_equal [MON], task.weekdays
    assert_equal [], task.month_weeks
    assert_equal 'day_of_month', task.monthly_mode

    task = valid_task(interval_units: 'month', monthly_mode: 'day_of_month', month_weeks: [1], weekdays: [MON])
    assert task.save
    task.reload
    assert_equal [], task.weekdays
    assert_equal [], task.month_weeks
  end

  def test_existing_records_without_recurrence_columns_behave_as_before
    task = valid_task(interval_units: 'week', next_run_date: Time.utc(2026, 1, 6, 10, 0, 0))
    task.save!
    task.update_columns(weekdays: nil, month_weeks: nil, monthly_mode: nil)
    task.reload

    assert_equal [], task.weekdays
    assert_equal [], task.month_weeks
    assert_equal 'day_of_month', task.monthly_mode
    assert_equal Time.utc(2026, 1, 13, 10, 0, 0), task.get_next_run_date(Time.utc(2026, 1, 6, 10, 5, 0))
  end

  def test_ordered_weekdays_start_on_the_configured_first_day_of_week
    with_settings start_of_week: '1' do
      assert_equal [1, 2, 3, 4, 5, 6, 0], Periodictask.ordered_weekdays
    end
    with_settings start_of_week: '7' do
      assert_equal [0, 1, 2, 3, 4, 5, 6], Periodictask.ordered_weekdays
    end
    with_settings start_of_week: '6' do
      assert_equal [6, 0, 1, 2, 3, 4, 5], Periodictask.ordered_weekdays
    end
  end

  # ---- scheduler integration ----

  def test_checker_generates_one_issue_per_selected_weekday_and_keeps_the_time
    task = valid_task(interval_units: 'week', weekdays: [MON, WED], next_run_date: Time.utc(2026, 1, 5, 10, 0, 0))
    task.save!

    # Mon 10:00 run (a few minutes late), then Wed 10:00 run (over an hour late)
    travel_to Time.utc(2026, 1, 5, 10, 4, 0) do
      assert_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    end
    assert_equal Time.utc(2026, 1, 7, 10, 0, 0), task.reload.next_run_date

    travel_to Time.utc(2026, 1, 6, 10, 0, 0) do
      assert_no_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    end

    travel_to Time.utc(2026, 1, 7, 11, 30, 0) do
      assert_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    end
    assert_equal Time.utc(2026, 1, 12, 10, 0, 0), task.reload.next_run_date
    assert_equal 2, task.created_issues.count
    assert_nil task.last_error
  end

  def test_checker_after_downtime_creates_one_issue_and_skips_to_next_future_occurrence
    task = valid_task(interval_units: 'month', monthly_mode: 'weekday', month_weeks: [1, 3], weekdays: [WED],
                      next_run_date: Time.utc(2026, 1, 7, 10, 0, 0))
    task.save!

    travel_to Time.utc(2026, 2, 10, 8, 0, 0) do # missed Jan 7, Jan 21 and Feb 4
      assert_difference('Issue.count', 1) { ScheduledTasksChecker.checktasks! }
    end
    assert_equal Time.utc(2026, 2, 18, 10, 0, 0), task.reload.next_run_date
  end

  private

  def weekly(anchor, weekdays, interval_number = 1)
    Periodictask.new(interval_number: interval_number, interval_units: 'week',
                     weekdays: weekdays, next_run_date: anchor)
  end

  def monthly_weekdays(anchor, month_weeks, weekdays, interval_number = 1)
    Periodictask.new(interval_number: interval_number, interval_units: 'month', monthly_mode: 'weekday',
                     month_weeks: month_weeks, weekdays: weekdays, next_run_date: anchor)
  end

  def valid_task(attrs = {})
    Periodictask.new({ project: @project, tracker_id: 1, author_id: 1, assigned_to_id: 2,
                       subject: 'Recurrence', interval_number: 1 }.merge(attrs))
  end

  def with_time_zone(name)
    original = Time.zone
    Time.zone = name
    yield
  ensure
    Time.zone = original
  end
end
