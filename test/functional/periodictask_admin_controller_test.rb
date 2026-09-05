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

  def test_index_lists_tasks_of_every_project
    create_test_periodictask(Project.find(1), subject: 'Task on ecookbook')
    create_test_periodictask(Project.find(2), subject: 'Task on onlinestore')

    log_user('admin', 'admin')
    get '/admin/periodictasks'
    assert_response :success
    assert_select 'table.list td.subject a', text: 'Task on ecookbook'
    assert_select 'table.list td.subject a', text: 'Task on onlinestore'
  end

  def test_index_is_sortable_by_each_column
    log_user('admin', 'admin')
    %w[project subject next_run_date].each do |column|
      get '/admin/periodictasks', params: { sort: "#{column}:desc" }
      assert_response :success, "sorting by #{column} should not error"
    end
  end

  def test_index_shows_an_empty_state
    Periodictask.delete_all

    log_user('admin', 'admin')
    get '/admin/periodictasks'
    assert_response :success
    assert_select 'p.nodata'
  end

  def test_index_requires_admin
    log_user('jsmith', 'jsmith')
    get '/admin/periodictasks'
    assert_response :forbidden
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

  private

  def create_test_periodictask(project, attrs = {})
    Periodictask.create!({
      project: project,
      tracker_id: 1,
      assigned_to_id: 2,
      author_id: 2,
      subject: 'Test task',
      interval_number: 1,
      interval_units: 'month',
      next_run_date: 1.month.from_now
    }.merge(attrs))
  end
end
