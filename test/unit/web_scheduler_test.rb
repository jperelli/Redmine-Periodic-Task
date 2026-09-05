require "#{File.dirname(__FILE__)}/../test_helper"

class WebSchedulerTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issue_categories

  def setup
    Periodictask.delete_all
    PeriodictaskSchedulerLock.delete_all
    RedminePeriodictask::WebScheduler.reset!
    RedminePeriodictask::WebScheduler.synchronous = true
    Setting.plugin_periodictask = { 'scheduler_mode' => 'web', 'web_check_interval' => 5 }
    @due_task = Periodictask.create!(project_id: 1, tracker_id: 1, author_id: 2, assigned_to_id: 2,
                                     subject: 'Due task', interval_number: 1, interval_units: 'day',
                                     next_run_date: 1.hour.ago)
  end

  def teardown
    RedminePeriodictask::WebScheduler.synchronous = false
    RedminePeriodictask::WebScheduler.reset!
    Setting.plugin_periodictask = { 'scheduler_mode' => 'cron' }
  end

  def test_does_nothing_in_cron_mode
    Setting.plugin_periodictask = { 'scheduler_mode' => 'cron' }
    assert_equal false, RedminePeriodictask::WebScheduler.maybe_run!
    assert_equal 0, PeriodictaskIssue.where(periodictask_id: @due_task.id).count
  end

  def test_runs_due_tasks_once_per_interval
    assert_equal true, RedminePeriodictask::WebScheduler.maybe_run!
    assert_equal 1, PeriodictaskIssue.where(periodictask_id: @due_task.id).count
    assert @due_task.reload.next_run_date > Time.current

    # second call within the interval is a no-op (per-process throttle)
    assert_equal false, RedminePeriodictask::WebScheduler.maybe_run!

    # another process (throttle reset) still loses the DB lock
    RedminePeriodictask::WebScheduler.reset!
    assert_equal false, RedminePeriodictask::WebScheduler.maybe_run!
  end

  def test_runs_again_after_interval_elapsed
    assert_equal true, RedminePeriodictask::WebScheduler.maybe_run!
    travel 6.minutes do
      Periodictask.update_all(next_run_date: 1.minute.ago)
      RedminePeriodictask::WebScheduler.reset!
      assert_equal true, RedminePeriodictask::WebScheduler.maybe_run!
    end
    assert_equal 2, PeriodictaskIssue.where(periodictask_id: @due_task.id).count
  end

  def test_lock_claim_is_exclusive
    assert PeriodictaskSchedulerLock.claim?(5.minutes)
    assert_not PeriodictaskSchedulerLock.claim?(5.minutes)
    assert PeriodictaskSchedulerLock.claim?(5.minutes, 6.minutes.from_now)
  end

  def test_interval_defaults_when_setting_is_invalid
    Setting.plugin_periodictask = { 'scheduler_mode' => 'web', 'web_check_interval' => '0' }
    assert_equal 5.minutes, RedminePeriodictask::WebScheduler.interval
    Setting.plugin_periodictask = { 'scheduler_mode' => 'web', 'web_check_interval' => '30' }
    assert_equal 30.minutes, RedminePeriodictask::WebScheduler.interval
  end
end
