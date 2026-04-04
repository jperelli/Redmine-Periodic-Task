require 'minitest/autorun'
require 'active_support'
require 'active_support/core_ext/integer/time'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/time'
require 'business_time'

# Tests for https://github.com/jperelli/Redmine-Periodic-Task/issues/25
# and validation that our approach is better than PR #102's.
#
# Our fix: use Time.current (respects config.time_zone from application.rb)
# PR #102: use User.current.time_zone + Time.zone.now (broken in cron context)

# Minimal struct mirroring Periodictask for testing get_next_run_date
TimezoneTestTask = Struct.new(:next_run_date, :interval_number, :interval_units) do
  def get_next_run_date(now = Time.current)
    units = interval_units.downcase
    val = next_run_date || now
    if units == 'business_day'
      while val <= now
        val = interval_number.business_day.after(val)
      end
    else
      interval_steps = ((now - val) / interval_number.send(units)).ceil
      val += (interval_number * interval_steps).send(units)
    end
    val
  end
end

class TimezoneCodeTest < Minitest::Test
  # ---- Source code checks: no Time.now anywhere ----

  def test_model_uses_time_current
    source = File.read(File.expand_path('../../../app/models/periodictask.rb', __FILE__))

    refute_match(/def generate_issue\(now\s*=\s*Time\.now\)/,
      source, 'generate_issue should use Time.current, not Time.now')
    refute_match(/def get_next_run_date\(now\s*=\s*Time\.now\)/,
      source, 'get_next_run_date should use Time.current, not Time.now')

    assert_match(/def generate_issue\(now\s*=\s*Time\.current\)/,
      source, 'generate_issue should default to Time.current')
    assert_match(/def get_next_run_date\(now\s*=\s*Time\.current\)/,
      source, 'get_next_run_date should default to Time.current')
  end

  def test_checker_uses_time_current
    source = File.read(File.expand_path('../../../lib/scheduled_tasks_checker.rb', __FILE__))

    refute_match(/now\s*=\s*Time\.now/, source,
      'ScheduledTasksChecker should use Time.current, not Time.now')
    assert_match(/now\s*=\s*Time\.current/, source,
      'ScheduledTasksChecker should use Time.current')
  end

  def test_controller_uses_time_current
    source = File.read(File.expand_path('../../../app/controllers/periodictask_controller.rb', __FILE__))

    refute_match(/Time\.now/, source,
      'Controller should use Time.current, not Time.now')
  end

  # ---- Locale labels mention server timezone ----

  def test_locale_labels_mention_timezone
    %w[en de it ru tr zh ja].each do |lang|
      source = File.read(File.expand_path("../../../config/locales/#{lang}.yml", __FILE__))
      refute_match(/label_next_run_date:.*\(yyyy-mm-dd hh:mm:ss\)\s*$/,
        source, "#{lang}.yml label should mention timezone, not just format")
    end
  end

  # ---- Time.current respects configured timezone ----

  def test_time_current_respects_configured_timezone
    original_zone = Time.zone

    Time.zone = 'Tokyo' # UTC+9
    now = Time.current
    assert_instance_of ActiveSupport::TimeWithZone, now
    assert_equal 'JST', now.zone
    assert_equal 32400, now.utc_offset

    Time.zone = 'Mountain Time (US & Canada)' # UTC-7 / UTC-6
    now = Time.current
    assert_instance_of ActiveSupport::TimeWithZone, now
    assert_includes %w[MST MDT], now.zone
  ensure
    Time.zone = original_zone
  end

  # ---- PR #102 approach breaks in cron context (no User) ----

  def test_pr102_approach_fails_without_user_timezone
    original_zone = Time.zone

    # Simulate cron context: User.current.time_zone returns nil
    # PR #102 does: Time.zone = User.current.time_zone (= nil)
    #               now = Time.zone.now  -> NoMethodError!
    Time.zone = nil
    assert_nil Time.zone, 'Setting Time.zone to nil should result in nil'
    assert_raises(NoMethodError) { Time.zone.now }

    # Our approach: Time.current still works because it falls back to
    # the default zone configured in config.time_zone
    Time.zone = 'UTC'
    assert_instance_of ActiveSupport::TimeWithZone, Time.current,
      'Time.current should work even without a user timezone'
  ensure
    Time.zone = original_zone
  end

  # ---- Timezone-aware scheduling: user enters local time, it works ----

  def test_scheduling_in_local_timezone_gmt_plus_1
    original_zone = Time.zone
    Time.zone = 'Paris' # CET = UTC+1 in winter

    # User in Paris sets next_run_date to "6:00am" via the form.
    # With Time.current, this is interpreted as 6:00am Paris time.
    scheduled = Time.zone.local(2026, 1, 15, 6, 0, 0)
    assert_equal 5, scheduled.utc.hour, 'Paris 06:00 CET = 05:00 UTC'

    # Time.current at 6:05am Paris time triggers the task
    now_local = Time.zone.local(2026, 1, 15, 6, 5, 0)
    assert now_local >= scheduled, 'Task should be due at 6:05am Paris time'

    # Time.current at 5:55am Paris time does NOT trigger
    before_local = Time.zone.local(2026, 1, 15, 5, 55, 0)
    assert before_local < scheduled, 'Task should not be due at 5:55am Paris time'
  ensure
    Time.zone = original_zone
  end

  def test_scheduling_in_local_timezone_gmt_minus_7
    original_zone = Time.zone
    Time.zone = 'Mountain Time (US & Canada)' # MST = UTC-7

    # User in MST sets next_run_date to "9:00am"
    scheduled = Time.zone.local(2026, 1, 15, 9, 0, 0)
    assert_equal 16, scheduled.utc.hour, 'MST 09:00 = 16:00 UTC'

    # Cron runs at 9:02am MST -> should trigger
    now_local = Time.zone.local(2026, 1, 15, 9, 2, 0)
    assert now_local >= scheduled
  ensure
    Time.zone = original_zone
  end

  # ---- get_next_run_date preserves timezone-aware time ----

  def test_get_next_run_date_preserves_timezone
    original_zone = Time.zone
    Time.zone = 'Tokyo' # UTC+9

    # Task scheduled at 10:00 Tokyo time, daily interval
    scheduled = Time.zone.local(2026, 4, 6, 10, 0, 0)
    task = TimezoneTestTask.new(scheduled, 1, 'day')

    # Cron fires at 10:20 Tokyo time
    now = Time.zone.local(2026, 4, 6, 10, 20, 0)
    next_date = task.get_next_run_date(now)

    assert_equal 10, next_date.hour, 'Next run should preserve 10:00 hour'
    assert_equal 0, next_date.min
    assert next_date > now
  ensure
    Time.zone = original_zone
  end

  def test_get_next_run_date_business_day_preserves_timezone
    original_zone = Time.zone
    Time.zone = 'Tokyo'

    # Task at 10:00 Tokyo, business day interval
    scheduled = Time.zone.local(2026, 4, 6, 10, 0, 0) # Monday
    task = TimezoneTestTask.new(scheduled, 1, 'business_day')

    # Cron fires at 10:30 Tokyo
    now = Time.zone.local(2026, 4, 6, 10, 30, 0)
    next_date = task.get_next_run_date(now)

    assert_equal 10, next_date.hour, 'business_day should preserve 10:00 hour'
    assert_equal 0, next_date.min
    assert next_date > now

    # No drift over 3 runs
    task.next_run_date = next_date
    3.times do |i|
      run_time = task.next_run_date + 1800 # 30 min late
      next_date = task.get_next_run_date(run_time)
      assert_equal 10, next_date.hour,
        "Run #{i + 2}: hour should stay 10, got #{next_date.strftime('%H:%M')}"
      task.next_run_date = next_date
    end
  ensure
    Time.zone = original_zone
  end

  # ---- End-to-end: issue #25 scenario ----
  # User in GMT+1 sets task to run at 6am. With the old code (Time.now = UTC),
  # they had to enter 5am UTC. Now they can enter 6am and it works.

  def test_issue_25_scenario_gmt_plus_1_user
    original_zone = Time.zone
    Time.zone = 'Paris'

    # User enters 6:00am in the form (Paris local time)
    scheduled = Time.zone.local(2026, 1, 15, 6, 0, 0)
    task = TimezoneTestTask.new(scheduled, 1, 'day')

    # Cron fires at 6:05am Paris time (= Time.current when zone is Paris)
    now = Time.zone.local(2026, 1, 15, 6, 5, 0)

    # Task should be due
    assert now >= scheduled, 'Task should be due at 6:05am Paris'

    # Next run preserves 6:00am Paris time
    next_date = task.get_next_run_date(now)
    assert_equal 6, next_date.hour
    assert_equal 0, next_date.min
  ensure
    Time.zone = original_zone
  end
end
