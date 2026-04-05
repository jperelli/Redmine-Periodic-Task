require File.dirname(__FILE__) + '/../test_helper'

class PeriodictaskControllerTest < ActionController::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issue_categories

  def setup
    @project = Project.find(1)
    EnabledModule.create!(project: @project, name: 'periodictask')

    role = Role.find(1) # Manager
    role.add_permission!(:periodictask) unless role.has_permission?(:periodictask)

    # Log in as jsmith (member of ecookbook with Manager role)
    @request.session[:user_id] = 2
  end

  def test_plugin_is_registered
    plugin = Redmine::Plugin.find(:periodictask)
    assert_not_nil plugin
    assert_equal 'Redmine Periodictask plugin', plugin.name
  end

  def test_index
    get :index, params: { project_id: 'ecookbook' }
    assert_response :success
  end

  def test_index_shows_existing_tasks
    create_test_periodictask(subject: 'Recurring security check')
    get :index, params: { project_id: 'ecookbook' }
    assert_response :success
  end

  def test_new
    get :new, params: { project_id: 'ecookbook' }
    assert_response :success
  end

  def test_create_periodictask
    assert_difference('Periodictask.count') do
      post :create, params: {
        project_id: 'ecookbook',
        periodictask: {
          subject: 'Test periodic task',
          description: 'A test description',
          tracker_id: 1,
          assigned_to_id: 2,
          interval_number: 1,
          interval_units: 'month',
          next_run_date: 1.month.from_now.to_s
        }
      }
    end
    assert_redirected_to controller: 'periodictask', action: 'index', project_id: 'ecookbook'

    task = Periodictask.order(:id).last
    assert_equal 'Test periodic task', task.subject
    assert_equal 'A test description', task.description
    assert_equal 1, task.interval_number
    assert_equal 'month', task.interval_units
    assert_equal @project.id, task.project_id
  end

  def test_create_with_missing_interval_fails
    assert_no_difference('Periodictask.count') do
      post :create, params: {
        project_id: 'ecookbook',
        periodictask: {
          subject: 'Bad task',
          tracker_id: 1,
          interval_number: nil,
          interval_units: 'month'
        }
      }
    end
    assert_response :success # re-renders the 'new' form
  end

  def test_edit
    task = create_test_periodictask
    get :edit, params: { project_id: 'ecookbook', id: task.id }
    assert_response :success
  end

  def test_update
    task = create_test_periodictask
    patch :update, params: {
      project_id: 'ecookbook',
      id: task.id,
      periodictask: {
        subject: 'Updated subject',
        interval_number: 2,
        interval_units: 'week'
      }
    }
    assert_redirected_to controller: 'periodictask', action: 'index', project_id: 'ecookbook'

    task.reload
    assert_equal 'Updated subject', task.subject
    assert_equal 2, task.interval_number
    assert_equal 'week', task.interval_units
  end

  def test_destroy
    task = create_test_periodictask
    assert_difference('Periodictask.count', -1) do
      delete :destroy, params: { project_id: 'ecookbook', id: task.id }
    end
    assert_redirected_to controller: 'periodictask', action: 'index', project_id: 'ecookbook'
  end

  def test_requires_login
    @request.session[:user_id] = nil
    Setting.login_required = '1'
    get :index, params: { project_id: 'ecookbook' }
    assert_response 302 # redirect to login
  ensure
    Setting.login_required = '0'
  end

  private

  def create_test_periodictask(attrs = {})
    Periodictask.create!({
      project: @project,
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
