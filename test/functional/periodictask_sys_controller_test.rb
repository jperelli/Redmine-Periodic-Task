require "#{File.dirname(__FILE__)}/../test_helper"

class PeriodictaskSysControllerTest < ActionController::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issue_categories

  def setup
    Periodictask.delete_all
    Setting.sys_api_enabled = '1'
    Setting.sys_api_key = 'secret-key'
    @due_task = Periodictask.create!(project_id: 1, tracker_id: 1, author_id: 2, assigned_to_id: 2,
                                     subject: 'Due task', interval_number: 1, interval_units: 'day',
                                     next_run_date: 1.hour.ago)
  end

  def teardown
    Setting.sys_api_enabled = '0'
  end

  def test_check_runs_due_tasks_with_valid_key
    get :check, params: { key: 'secret-key' }
    assert_response :success
    assert_match(/1 task\(s\) run/, @response.body)
    assert_equal 1, PeriodictaskIssue.where(periodictask_id: @due_task.id).count
  end

  def test_check_accepts_post
    post :check, params: { key: 'secret-key' }
    assert_response :success
  end

  def test_check_denied_with_wrong_key
    get :check, params: { key: 'wrong' }
    assert_response :forbidden
    assert_equal 0, PeriodictaskIssue.where(periodictask_id: @due_task.id).count
  end

  def test_check_denied_when_sys_api_disabled
    Setting.sys_api_enabled = '0'
    get :check, params: { key: 'secret-key' }
    assert_response :forbidden
  end
end
