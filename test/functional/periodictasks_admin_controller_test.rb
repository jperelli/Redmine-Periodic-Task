require "#{File.dirname(__FILE__)}/../test_helper"

class PeriodictasksAdminControllerTest < ActionController::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations

  def setup
    @request.session[:user_id] = 1 # admin
  end

  def test_index_lists_tasks_of_every_project
    create_test_periodictask(Project.find(1), subject: 'Task on ecookbook')
    create_test_periodictask(Project.find(2), subject: 'Task on onlinestore')

    get :index
    assert_response :success
    assert_select 'table.list td.subject a', text: 'Task on ecookbook'
    assert_select 'table.list td.subject a', text: 'Task on onlinestore'
  end

  def test_index_is_sortable_by_each_column
    create_test_periodictask(Project.find(1))

    %w[project subject next_run_date].each do |column|
      get :index, params: { sort: "#{column}:desc" }
      assert_response :success, "sorting by #{column} should not error"
    end
  end

  def test_index_shows_an_empty_state
    get :index
    assert_response :success
    assert_select 'p.nodata'
  end

  def test_index_requires_admin
    @request.session[:user_id] = 2 # jsmith, not an admin
    get :index
    assert_response 403
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
