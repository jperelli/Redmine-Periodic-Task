require "#{File.dirname(__FILE__)}/../test_helper"

# Any Redmine controller request triggers the web scheduler when enabled.
class WebSchedulerRequestTest < Redmine::IntegrationTest
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issue_categories

  def setup
    Periodictask.delete_all
    PeriodictaskSchedulerLock.delete_all
    RedminePeriodictask::WebScheduler.reset!
    RedminePeriodictask::WebScheduler.synchronous = true
    @due_task = Periodictask.create!(project_id: 1, tracker_id: 1, author_id: 2, assigned_to_id: 2,
                                     subject: 'Due task', interval_number: 1, interval_units: 'day',
                                     next_run_date: 1.hour.ago)
  end

  def teardown
    RedminePeriodictask::WebScheduler.synchronous = false
    RedminePeriodictask::WebScheduler.reset!
    Setting.plugin_periodictask = { 'scheduler_mode' => 'cron' }
  end

  def test_request_triggers_checker_in_web_mode
    Setting.plugin_periodictask = { 'scheduler_mode' => 'web', 'web_check_interval' => 5 }
    get '/'
    assert_response :success
    assert_equal 1, PeriodictaskIssue.where(periodictask_id: @due_task.id).count
  end

  def test_request_does_not_trigger_checker_in_cron_mode
    Setting.plugin_periodictask = { 'scheduler_mode' => 'cron' }
    get '/'
    assert_response :success
    assert_equal 0, PeriodictaskIssue.where(periodictask_id: @due_task.id).count
  end
end
