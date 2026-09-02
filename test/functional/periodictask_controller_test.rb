require "#{File.dirname(__FILE__)}/../test_helper"

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

  def test_index_is_sortable_by_each_column
    create_test_periodictask(subject: 'Sortable task')
    %w[id interval next_run_date tracker priority subject assigned_to last_run].each do |column|
      get :index, params: { project_id: 'ecookbook', sort: "#{column}:desc" }
      assert_response :success, "sorting by #{column} should not error"
    end
  end

  def test_index_sort_by_interval_uses_duration_not_raw_number
    create_test_periodictask(subject: 'One day', interval_number: 1, interval_units: 'day')
    create_test_periodictask(subject: 'One week', interval_number: 1, interval_units: 'week')
    create_test_periodictask(subject: 'One year', interval_number: 1, interval_units: 'year')
    get :index, params: { project_id: 'ecookbook', sort: 'interval:asc' }
    assert_response :success
    body = @response.body
    assert_operator body.index('One day'), :<, body.index('One week')
    assert_operator body.index('One week'), :<, body.index('One year')
  end

  def test_index_orders_by_id_desc_by_default
    create_test_periodictask(subject: 'Older task')
    create_test_periodictask(subject: 'Newer task')
    get :index, params: { project_id: 'ecookbook' }
    assert_response :success
    # Default sort is id desc, so the most recently created task appears first.
    assert_operator @response.body.index('Newer task'), :<,
                    @response.body.index('Older task')
  end

  def test_new
    get :new, params: { project_id: 'ecookbook' }
    assert_response :success
  end

  def test_new_displays_tracker_default_status_option
    status = IssueStatus.find(2)
    Tracker.find(1).update!(default_status: status)

    get :new, params: { project_id: 'ecookbook' }

    assert_select '#periodictask_status_id option:first-child[value=""]',
                  text: "(#{I18n.t(:label_default)}) - #{status.name}"
  end

  def test_new_displays_configured_default_priority_option
    priority = IssuePriority.where.not(id: IssuePriority.default.id).first
    IssuePriority.update_all(is_default: false)
    priority.update!(is_default: true)

    get :new, params: { project_id: 'ecookbook' }

    assert_select '#periodictask_priority_id option:first-child[value=""]',
                  text: "(#{I18n.t(:label_default)}) - #{priority.name}"
  end

  def test_create_periodictask
    assert_difference('Periodictask.count') do
      post :create, params: {
        project_id: 'ecookbook',
        periodictask: {
          subject: 'Test periodic task',
          description: 'A test description',
          tracker_id: 1,
          status_id: 5,
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
    assert_equal 5, task.status_id
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

  def test_edit_selects_configured_status
    task = create_test_periodictask(status_id: 5)

    get :edit, params: { project_id: 'ecookbook', id: task.id }

    assert_select '#periodictask_status_id option[selected="selected"][value="5"]'
  end

  def test_edit_with_nil_watcher_user_ids
    task = create_test_periodictask
    task.update_column(:watcher_user_ids, nil)

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

  def test_update_parses_next_run_date_in_user_time_zone
    User.find(2).pref.update!(time_zone: 'Buenos Aires') # UTC-3, no DST
    task = create_test_periodictask
    patch :update, params: {
      project_id: 'ecookbook',
      id: task.id,
      periodictask: { next_run_date: '2026-08-20T09:00' }
    }
    task.reload
    assert_equal Time.utc(2026, 8, 20, 12, 0), task.next_run_date.utc
    assert_equal '2026-08-20 09:00', task.next_run_date.in_time_zone('Buenos Aires').strftime('%Y-%m-%d %H:%M')
  end

  def test_edit_shows_next_run_date_and_zone_in_user_time_zone
    User.find(2).pref.update!(time_zone: 'Buenos Aires')
    task = create_test_periodictask(next_run_date: Time.utc(2026, 8, 20, 12, 0))

    get :edit, params: { project_id: 'ecookbook', id: task.id }

    assert_select '#periodictask_next_run_date[value="2026-08-20T09:00"]'
    assert_select 'span.periodictask-time-zone a[href=?][target="_blank"]', '/my/account',
                  text: '(GMT-03:00) Buenos Aires'
  end

  def test_next_run_date_round_trips_in_server_zone_without_user_time_zone
    User.find(2).pref.update!(time_zone: '')
    task = create_test_periodictask
    patch :update, params: {
      project_id: 'ecookbook',
      id: task.id,
      periodictask: { next_run_date: '2026-08-20T10:00' }
    }
    task.reload
    assert_equal '2026-08-20 10:00', task.next_run_date.getlocal.strftime('%Y-%m-%d %H:%M')

    get :edit, params: { project_id: 'ecookbook', id: task.id }
    assert_select '#periodictask_next_run_date[value="2026-08-20T10:00"]'
  end

  def test_show
    task = create_test_periodictask
    get :show, params: { project_id: 'ecookbook', id: task.id }
    assert_response :success
  end

  def test_show_displays_status_first_in_left_issue_attributes
    task = create_test_periodictask(status_id: 5)

    get :show, params: { project_id: 'ecookbook', id: task.id }

    assert_select '.periodictask-template .attributes .splitcontentleft > .status:first-child',
                  text: /#{Regexp.escape(IssueStatus.find(5).name)}/
  end

  def test_show_displays_tracker_default_for_unconfigured_status
    task = create_test_periodictask(status_id: nil)
    task.tracker.update!(default_status_id: 2)

    get :show, params: { project_id: 'ecookbook', id: task.id }

    assert_select '.periodictask-template .attributes .status .value',
                  text: "(#{I18n.t(:label_default)}) - Assigned"
  end

  def test_show_displays_configured_default_for_unconfigured_priority
    task = create_test_periodictask(priority_id: nil)
    priority = IssuePriority.where.not(id: IssuePriority.default.id).first
    IssuePriority.update_all(is_default: false)
    priority.update!(is_default: true)

    get :show, params: { project_id: 'ecookbook', id: task.id }

    assert_select '.periodictask-template .attributes .priority .value',
                  text: "(#{I18n.t(:label_default)}) - #{priority.name}"
  end

  def test_show_lists_generated_issues
    task = create_test_periodictask(next_run_date: 1.day.ago)
    ScheduledTasksChecker.checktasks!
    get :show, params: { project_id: 'ecookbook', id: task.id }
    assert_response :success
    assert_equal 1, task.created_issues.count
  end

  def test_destroy
    task = create_test_periodictask
    assert_difference('Periodictask.count', -1) do
      delete :destroy, params: { project_id: 'ecookbook', id: task.id }
    end
    assert_redirected_to controller: 'periodictask', action: 'index', project_id: 'ecookbook'
  end

  def test_run_now_creates_issue_and_records_history
    task = create_test_periodictask(next_run_date: 1.month.from_now)
    assert_difference('Issue.count', 1) do
      post :run_now, params: { project_id: 'ecookbook', id: task.id }
    end
    assert_redirected_to controller: 'periodictask', action: 'index', project_id: 'ecookbook'
    assert_equal 1, task.created_issues.count
  end

  def test_run_now_redirects_back_to_referer
    task = create_test_periodictask
    @request.env['HTTP_REFERER'] = "/projects/ecookbook/periodictask/#{task.id}"
    post :run_now, params: { project_id: 'ecookbook', id: task.id }
    assert_redirected_to controller: 'periodictask', action: 'show', id: task.id, project_id: 'ecookbook'
  end

  def test_run_now_does_not_advance_schedule
    next_run = 1.month.from_now
    task = create_test_periodictask(next_run_date: next_run)
    post :run_now, params: { project_id: 'ecookbook', id: task.id }
    task.reload
    assert_in_delta next_run.to_i, task.next_run_date.to_i, 1
  end

  def test_requires_login
    @request.session[:user_id] = nil
    Setting.login_required = '1'
    get :index, params: { project_id: 'ecookbook' }
    assert_response 302 # redirect to login
  ensure
    Setting.login_required = '0'
  end

  def test_denies_member_without_permission
    # dlopez (user 3) is a Developer member of ecookbook but the Developer role
    # was not granted the :periodictask permission in setup.
    @request.session[:user_id] = 3
    get :index, params: { project_id: 'ecookbook' }
    assert_response 403
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
