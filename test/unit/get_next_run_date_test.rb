require 'minitest/autorun'
require 'active_support'
require 'active_support/core_ext/integer/time'
require 'active_support/core_ext/numeric/time'
require 'business_time'

# Standalone test for get_next_run_date logic (no Redmine dependency needed).
# Tests the fix for https://github.com/jperelli/Redmine-Periodic-Task/issues/79
# where business_day intervals caused next_run_date to drift based on
# actual execution time rather than the originally scheduled time.

# Minimal struct that mirrors the relevant Periodictask attributes
# and includes the get_next_run_date method under test.
GetNextRunDateTestTask = Struct.new(:next_run_date, :interval_number, :interval_units) do
  def get_next_run_date(now = Time.now)
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

class GetNextRunDateTest < Minitest::Test
  # Issue #79: business_day next_run_date should NOT drift with execution time.
  # When a task is scheduled within business hours (e.g. 10:00) and cron runs
  # late (e.g. 10:35), the next run should be based on the original 10:00, not 10:35.
  def test_business_day_does_not_drift_with_execution_time
    # Task scheduled at 10:00 UTC (within business hours)
    scheduled_time = Time.utc(2026, 4, 6, 10, 0, 0) # Monday 10:00 UTC
    task = GetNextRunDateTestTask.new(scheduled_time, 1, 'business_day')

    # Cron fires 35 min late
    execution_time = Time.utc(2026, 4, 6, 10, 35, 0)

    next_date = task.get_next_run_date(execution_time)

    # Next run should preserve 10:00 from original schedule, NOT use 10:35
    assert_equal 10, next_date.hour,
      "Expected next run hour to be 10:00 (original schedule), got #{next_date.strftime('%H:%M')}"
    assert_equal 0, next_date.min,
      "Expected next run minute to be :00, got #{next_date.strftime('%H:%M')}"
    assert next_date > execution_time,
      "Next run date should be in the future relative to execution time"
  end

  # Verify that running the same scenario multiple times doesn't cause
  # cumulative drift (the core of issue #79).
  def test_business_day_no_cumulative_drift_over_multiple_runs
    # Initial schedule: Monday 10:00 UTC (within business hours)
    scheduled_time = Time.utc(2026, 4, 6, 10, 0, 0)
    task = GetNextRunDateTestTask.new(scheduled_time, 1, 'business_day')

    # Simulate 5 consecutive daily runs, each delayed by 30-35 min
    5.times do |i|
      execution_time = task.next_run_date + 1800 + rand(300) # 30-35 min late
      next_date = task.get_next_run_date(execution_time)

      assert_equal 10, next_date.hour,
        "Run #{i + 1}: Expected hour 10, got #{next_date.strftime('%H:%M:%S')}"
      assert_equal 0, next_date.min,
        "Run #{i + 1}: Expected minute 00, got #{next_date.strftime('%H:%M:%S')}"
      assert next_date > execution_time,
        "Run #{i + 1}: Next run date should be after execution time"

      # Update task's next_run_date as the checker would
      task.next_run_date = next_date
    end
  end

  # For times outside business hours, business_time snaps to start of business
  # day (09:00). Verify that once snapped, the time stays consistent and doesn't
  # drift further. This is the exact scenario from issue #79 (user sets 06:00).
  def test_business_day_outside_business_hours_stabilizes
    # Task originally at 06:00 (before business hours)
    scheduled_time = Time.utc(2026, 4, 6, 6, 0, 0) # Monday 06:00
    task = GetNextRunDateTestTask.new(scheduled_time, 1, 'business_day')

    # First run: cron at 07:05
    execution_time = Time.utc(2026, 4, 6, 7, 5, 0)
    next_date = task.get_next_run_date(execution_time)
    # business_time snaps to 09:00 (start of business day)
    assert_equal 9, next_date.hour
    assert_equal 0, next_date.min
    assert next_date > execution_time

    # Simulate subsequent runs - time should stay at 09:00
    task.next_run_date = next_date
    3.times do |i|
      execution_time = task.next_run_date + 1800 + rand(300) # 30-35 min late
      next_date = task.get_next_run_date(execution_time)

      assert_equal 9, next_date.hour,
        "Run #{i + 2}: Expected hour 09:00 (stable), got #{next_date.strftime('%H:%M')}"
      assert_equal 0, next_date.min,
        "Run #{i + 2}: Expected minute 00, got #{next_date.strftime('%H:%M')}"
      assert next_date > execution_time

      task.next_run_date = next_date
    end
  end

  # Verify business_day with interval > 1
  def test_business_day_multi_day_interval_preserves_time
    # Task scheduled at 14:00, every 3 business days
    scheduled_time = Time.utc(2026, 4, 6, 14, 0, 0) # Monday
    task = GetNextRunDateTestTask.new(scheduled_time, 3, 'business_day')

    execution_time = Time.utc(2026, 4, 6, 14, 45, 0) # runs 45m late

    next_date = task.get_next_run_date(execution_time)

    assert_equal 14, next_date.hour,
      "Expected hour 14, got #{next_date.strftime('%H:%M')}"
    assert_equal 0, next_date.min,
      "Expected minute 00, got #{next_date.strftime('%H:%M')}"
    assert next_date > execution_time
  end

  # Verify day interval still works correctly (regression test)
  def test_day_interval_preserves_scheduled_time
    scheduled_time = Time.utc(2026, 4, 6, 6, 0, 0)
    task = GetNextRunDateTestTask.new(scheduled_time, 1, 'day')

    execution_time = Time.utc(2026, 4, 6, 7, 5, 0)
    next_date = task.get_next_run_date(execution_time)

    assert_equal 6, next_date.hour,
      "Day interval: expected hour 06, got #{next_date.strftime('%H:%M')}"
    assert_equal 0, next_date.min
    assert next_date > execution_time
  end

  # Verify week interval still works correctly (regression test)
  def test_week_interval_preserves_scheduled_time
    scheduled_time = Time.utc(2026, 4, 6, 6, 0, 0) # Monday
    task = GetNextRunDateTestTask.new(scheduled_time, 1, 'week')

    execution_time = Time.utc(2026, 4, 6, 7, 5, 0)
    next_date = task.get_next_run_date(execution_time)

    assert_equal 6, next_date.hour
    assert_equal 0, next_date.min
    assert next_date > execution_time
  end
end
