require "#{File.dirname(__FILE__)}/../test_helper"

class PeriodictaskAdminControllerTest < Redmine::IntegrationTest
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issue_categories

  def setup
    Periodictask.delete_all
    PeriodictaskRun.delete_all
    @due_task = Periodictask.create!(project_id: 1, tracker_id: 1, author_id: 2, assigned_to_id: 2,
                                     subject: 'Due task', interval_number: 1, interval_units: 'day',
                                     next_run_date: 1.hour.ago)
  end

  def test_admin_can_run_checker_from_settings
    log_user('admin', 'admin')
    post '/admin/periodictask/run_checker'
    assert_redirected_to '/settings/plugin/periodictask'
    assert_equal 1, PeriodictaskIssue.where(periodictask_id: @due_task.id).count
    run = PeriodictaskRun.recent.first
    assert_equal 'manual', run.source
    assert_equal 1, run.issues_created

    follow_redirect!
    assert_select 'div.flash.notice', text: /1 task/
    assert_select 'table.periodictask-runs tbody tr', 1
    assert_select 'table.periodictask-runs td', text: 'Manual'
  end

  def test_non_admin_is_forbidden
    log_user('jsmith', 'jsmith')
    post '/admin/periodictask/run_checker'
    assert_response :forbidden
    assert_equal 0, PeriodictaskIssue.where(periodictask_id: @due_task.id).count
    assert_equal 0, PeriodictaskRun.count
  end

  def test_anonymous_is_redirected_to_login
    post '/admin/periodictask/run_checker'
    assert_response :redirect
    assert_equal 0, PeriodictaskRun.count
  end
end
