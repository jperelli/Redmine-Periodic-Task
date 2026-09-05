require "#{File.dirname(__FILE__)}/../test_helper"

class PeriodictaskControllerTest < ActionController::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issue_categories, :issues

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
          done_ratio: 40,
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
    assert_equal 40, task.done_ratio
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

  def test_edit_selects_configured_done_ratio
    task = create_test_periodictask(done_ratio: 70)

    get :edit, params: { project_id: 'ecookbook', id: task.id }

    assert_select '#periodictask_done_ratio option[selected="selected"][value="70"]'
  end

  def test_show_renders_done_ratio_progress_bar
    task = create_test_periodictask(done_ratio: 70)

    get :show, params: { project_id: 'ecookbook', id: task.id }

    assert_response :success
    assert_select '.progress.attribute table.progress td.closed[style*="width: 70%"]'
    assert_select '.progress.attribute p.percent', text: '70%'
  end

  def test_done_ratio_hidden_when_tracker_disables_it
    tracker = Tracker.find(1)
    tracker.core_fields = tracker.core_fields - ['done_ratio']
    tracker.save!
    task = create_test_periodictask(done_ratio: 70)

    get :edit, params: { project_id: 'ecookbook', id: task.id }
    assert_select '#periodictask_done_ratio_field[style*="display: none"]'
    assert_select '#periodictask_tracker_id option[value="1"][data-done-ratio-enabled="false"]'

    get :show, params: { project_id: 'ecookbook', id: task.id }
    assert_select '.progress.attribute', 0
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

  def test_tags_autocomplete_returns_empty_list_without_tagging_plugin
    skip 'a tagging plugin is installed' if Periodictask.tags_plugin_installed?

    get :tags, params: { project_id: 'ecookbook', term: 'op' }
    assert_response :success
    assert_equal [], JSON.parse(@response.body)
  end

  def test_create_stores_tag_list
    post :create, params: {
      project_id: 'ecookbook',
      periodictask: {
        subject: 'Tagged task', tracker_id: 1, assigned_to_id: 2, author_id: 2,
        interval_number: 1, interval_units: 'month', tag_list: 'ops, weekly'
      }
    }
    assert_response :redirect
    assert_equal 'ops, weekly', Periodictask.find_by(subject: 'Tagged task').tag_list
  end

  def test_create_stores_subtasks_and_relations
    post :create, params: {
      project_id: 'ecookbook',
      periodictask: {
        subject: 'With children', tracker_id: 1, assigned_to_id: 2, author_id: 2,
        interval_number: 1, interval_units: 'month',
        subtasks: { '0' => { tracker_id: '2', subject: 'Child A', assigned_to_id: '3', estimated_hours: '0:30' },
                    '1' => { tracker_id: '', subject: '', assigned_to_id: '', estimated_hours: '' } },
        relations: { '0' => { relation_type: 'precedes', issue_id: '1', delay: '2' } }
      }
    }
    assert_response :redirect

    task = Periodictask.find_by(subject: 'With children')
    expected = { 'tracker_id' => '2', 'subject' => 'Child A', 'assigned_to_id' => '3', 'estimated_hours' => 0.5 }
    assert_equal [expected], task.subtasks
    assert_equal [{ 'relation_type' => 'precedes', 'issue_id' => '1', 'delay' => '2' }], task.relations
  end

  def test_create_with_blank_subtask_subject_rerenders_form
    assert_no_difference('Periodictask.count') do
      post :create, params: {
        project_id: 'ecookbook',
        periodictask: {
          subject: 'Bad child', tracker_id: 1, assigned_to_id: 2, author_id: 2,
          interval_number: 1, interval_units: 'month',
          subtasks: { '0' => { tracker_id: '1', subject: '', assigned_to_id: '2' } }
        }
      }
    end
    assert_response :success
    assert_select '#errorExplanation', text: /#{I18n.t(:error_subtask_subject_blank)}/
  end

  def test_update_clears_subtasks_when_all_rows_removed
    task = create_test_periodictask(subtasks: [{ 'subject' => 'Child' }])
    patch :update, params: {
      project_id: 'ecookbook', id: task.id,
      periodictask: { subject: 'No children', interval_number: 1, interval_units: 'month' }
    }
    assert_response :redirect
    assert_equal [], task.reload.subtasks
  end

  def test_run_now_creates_subtasks_and_relations
    task = create_test_periodictask(next_run_date: 1.month.from_now,
                                    subtasks: [{ 'subject' => 'Child' }],
                                    relations: [{ 'relation_type' => 'relates', 'issue_id' => '1' }])
    assert_difference('Issue.count', 2) do
      assert_difference('IssueRelation.count', 1) do
        post :run_now, params: { project_id: 'ecookbook', id: task.id }
      end
    end
    assert_nil task.reload.last_error
    parent = task.created_issues.find_by(subject: task.subject)
    assert_equal ['Child'], parent.children.map(&:subject)
    assert_equal [1], parent.relations.map(&:issue_from_id)
    assert_equal 2, task.created_issues.count
  end

  def test_edit_renders_subtask_and_relation_rows
    task = create_test_periodictask(subtasks: [{ 'subject' => 'Child', 'tracker_id' => '2' }],
                                    relations: [{ 'relation_type' => 'blocks', 'issue_id' => '1' }])
    get :edit, params: { project_id: 'ecookbook', id: task.id }
    assert_response :success
    assert_select 'input[name=?][value=?]', 'periodictask[subtasks][0][subject]', 'Child'
    assert_select 'select[name=?] option[selected][value="2"]', 'periodictask[subtasks][0][tracker_id]'
    assert_select 'select[name=?] option[selected][value=blocks]', 'periodictask[relations][0][relation_type]'
    assert_select 'input[name=?][value="1"]', 'periodictask[relations][0][issue_id]'
  end

  def test_show_lists_subtasks_and_relations
    task = create_test_periodictask(subtasks: [{ 'subject' => 'Child' }],
                                    relations: [{ 'relation_type' => 'blocks', 'issue_id' => '1' }])
    get :show, params: { project_id: 'ecookbook', id: task.id }
    assert_response :success
    assert_select '.periodictask-subtasks td', text: 'Child'
    assert_select '.periodictask-relations li', text: /#{I18n.t(:label_blocks)}.*#1/m
  end

  # ---- recurrence (issue #50) ----

  def test_new_renders_recurrence_controls_as_checkboxes
    get :new, params: { project_id: 'ecookbook' }
    assert_response :success
    assert_select '#periodictask_weekdays_field input[type=checkbox][name=?]', 'periodictask[weekdays][]', count: 7
    assert_select '#periodictask_weekdays_field label', text: I18n.t('date.day_names')[1]
    assert_select '#periodictask_monthly_mode_field input[type=radio][name=?]', 'periodictask[monthly_mode]', count: 2
    assert_select '#periodictask_monthly_mode_field input[type=radio][value=day_of_month][checked]'
    assert_select '#periodictask_month_weeks_field input[type=checkbox][name=?]', 'periodictask[month_weeks][]',
                  count: 5
    assert_select '.periodictask-recurrence input[type=checkbox][checked]', count: 0
  end

  def test_form_and_last_error_link_to_recurrence_documentation
    task = create_test_periodictask(subject: 'Failed', last_error: 'Project is missing or closed')
    doc_url = RedminePeriodictask::RECURRENCE_DOC_URL

    get :new, params: { project_id: 'ecookbook' }
    assert_select 'a.icon-help[href=?][title=?]', doc_url, 'How schedules are calculated'

    get :show, params: { project_id: 'ecookbook', id: task.id }
    assert_select 'a.icon-help[href=?][title=?]', doc_url, 'Why a task may not have run as expected'

    get :edit, params: { project_id: 'ecookbook', id: task.id }
    assert_select 'a.icon-help[href=?]', doc_url, count: 2
  end

  def test_new_orders_weekday_checkboxes_by_start_of_week
    with_settings start_of_week: '1' do
      get :new, params: { project_id: 'ecookbook' }
      assert_equal %w[1 2 3 4 5 6 0], rendered_weekday_values
    end
    with_settings start_of_week: '7' do
      get :new, params: { project_id: 'ecookbook' }
      assert_equal %w[0 1 2 3 4 5 6], rendered_weekday_values
    end
  end

  def test_create_weekly_stores_weekdays_and_computes_blank_next_run_date_from_them
    travel_to Time.utc(2026, 1, 6, 10, 0, 0) do # Tuesday
      post :create, params: {
        project_id: 'ecookbook',
        periodictask: {
          subject: 'Weekly on Mon/Wed', tracker_id: 1, assigned_to_id: 2, author_id: 2,
          interval_number: 1, interval_units: 'week', next_run_date: '',
          weekdays: ['', '3', '1'], monthly_mode: 'weekday', month_weeks: ['', '2']
        }
      }
    end
    assert_response :redirect

    task = Periodictask.find_by(subject: 'Weekly on Mon/Wed')
    assert_equal [1, 3], task.weekdays
    assert_equal [], task.month_weeks
    assert_equal Time.utc(2026, 1, 7, 10, 0, 0), task.next_run_date
  end

  def test_create_monthly_weekday_stores_ordinals_and_weekdays
    travel_to Time.utc(2026, 1, 8, 9, 30, 0) do # Thursday after the 1st Wednesday
      post :create, params: {
        project_id: 'ecookbook',
        periodictask: {
          subject: 'Third Wednesday', tracker_id: 1, assigned_to_id: 2, author_id: 2,
          interval_number: 1, interval_units: 'month', next_run_date: '',
          monthly_mode: 'weekday', month_weeks: ['', '1', '3'], weekdays: ['', '3']
        }
      }
    end
    assert_response :redirect

    task = Periodictask.find_by(subject: 'Third Wednesday')
    assert_equal 'weekday', task.monthly_mode
    assert_equal [1, 3], task.month_weeks
    assert_equal [3], task.weekdays
    assert_equal Time.utc(2026, 1, 21, 9, 30, 0), task.next_run_date
  end

  def test_create_uses_explicit_next_run_date_as_first_run_even_if_not_a_selected_weekday
    User.find(2).pref.update!(time_zone: 'UTC')
    post :create, params: {
      project_id: 'ecookbook',
      periodictask: {
        subject: 'Explicit anchor', tracker_id: 1, assigned_to_id: 2, author_id: 2,
        interval_number: 1, interval_units: 'week', next_run_date: '2026-01-06T10:00', weekdays: ['1']
      }
    }
    assert_response :redirect
    task = Periodictask.find_by(subject: 'Explicit anchor')
    assert_equal Time.utc(2026, 1, 6, 10, 0, 0), task.next_run_date # a Tuesday, kept as the literal first run
    assert_equal [1], task.weekdays
  end

  def test_create_monthly_weekday_without_selection_rerenders_form_with_error
    assert_no_difference('Periodictask.count') do
      post :create, params: {
        project_id: 'ecookbook',
        periodictask: {
          subject: 'Incomplete', tracker_id: 1, assigned_to_id: 2, author_id: 2,
          interval_number: 1, interval_units: 'month',
          monthly_mode: 'weekday', month_weeks: ['', '1'], weekdays: ['']
        }
      }
    end
    assert_response :success
    assert_select '#errorExplanation', text: /#{I18n.t(:error_recurrence_weekdays_blank)}/
    assert_select '#periodictask_monthly_mode_field input[value=weekday][checked]'
    assert_select '#periodictask_month_weeks_field input[value="1"][checked]'
    assert_select '#periodictask_next_run_date[value]', count: 0 # the blank first run stays blank
  end

  def test_edit_renders_persisted_recurrence_selections
    task = create_test_periodictask(interval_units: 'month', monthly_mode: 'weekday',
                                    month_weeks: [1, 5], weekdays: [0, 3])
    get :edit, params: { project_id: 'ecookbook', id: task.id }
    assert_response :success
    assert_select '#periodictask_monthly_mode_field input[value=weekday][checked]'
    assert_select '#periodictask_month_weeks_field input[type=checkbox][checked]', count: 2
    assert_select '#periodictask_month_weeks_field input[value="1"][checked]'
    assert_select '#periodictask_month_weeks_field input[value="5"][checked]'
    assert_select '#periodictask_weekdays_field input[type=checkbox][checked]', count: 2
    assert_select '#periodictask_weekdays_field input[value="0"][checked]'
    assert_select '#periodictask_weekdays_field input[value="3"][checked]'
  end

  def test_update_clears_recurrence_options_when_unit_changes
    task = create_test_periodictask(interval_units: 'week', weekdays: [1, 3])
    patch :update, params: {
      project_id: 'ecookbook', id: task.id,
      periodictask: { interval_units: 'day', weekdays: ['', '1', '3'] }
    }
    assert_response :redirect
    task.reload
    assert_equal 'day', task.interval_units
    assert_equal [], task.weekdays
  end

  def test_update_replaces_weekday_selection
    task = create_test_periodictask(interval_units: 'week', weekdays: [1, 3])
    patch :update, params: {
      project_id: 'ecookbook', id: task.id,
      periodictask: { interval_units: 'week', weekdays: ['', '5'] }
    }
    task.reload
    assert_equal [5], task.weekdays

    patch :update, params: { project_id: 'ecookbook', id: task.id, periodictask: { interval_units: 'week' } }
    task.reload
    assert_equal [], task.weekdays
  end

  def test_index_and_show_describe_weekly_recurrence
    task = create_test_periodictask(subject: 'Weekly described', interval_number: 2, interval_units: 'week',
                                    weekdays: [3, 1])
    expected = 'every 2 weeks on Monday, Wednesday'

    get :index, params: { project_id: 'ecookbook' }
    assert_select 'td.interval', text: expected

    get :show, params: { project_id: 'ecookbook', id: task.id }
    assert_select '.interval .value', text: expected
  end

  def test_index_and_show_describe_monthly_weekday_recurrence
    task = create_test_periodictask(subject: 'Monthly described', interval_units: 'month', monthly_mode: 'weekday',
                                    month_weeks: [3, 1], weekdays: [3])
    expected = 'each month on the 1st, 3rd Wednesday'

    get :index, params: { project_id: 'ecookbook' }
    assert_select 'td.interval', text: expected

    get :show, params: { project_id: 'ecookbook', id: task.id }
    assert_select '.interval .value', text: expected
  end

  def test_index_and_show_describe_monthly_day_of_month_recurrence
    task = create_test_periodictask(subject: 'Day of month', interval_units: 'month',
                                    next_run_date: Time.utc(2026, 3, 15, 12, 0))
    expected = 'each month on day 15'

    get :index, params: { project_id: 'ecookbook' }
    assert_select 'td.interval', text: expected

    get :show, params: { project_id: 'ecookbook', id: task.id }
    assert_select '.interval .value', text: expected
  end

  def test_index_and_show_keep_plain_description_for_other_units
    task = create_test_periodictask(subject: 'Plain', interval_number: 3, interval_units: 'business_day')
    create_test_periodictask(subject: 'Daily', interval_number: 1, interval_units: 'day')
    expected = 'every 3 business days'

    get :index, params: { project_id: 'ecookbook' }
    assert_select 'td.interval', text: expected
    assert_select 'td.interval', text: 'each day'

    get :show, params: { project_id: 'ecookbook', id: task.id }
    assert_select '.interval .value', text: expected
  end

  def test_copy_prefills_the_new_form_without_saving
    task = create_test_periodictask(subject: 'Weekly backup', interval_number: 3,
                                    interval_units: 'week', description: 'Run the backup')

    assert_no_difference('Periodictask.count') do
      get :copy, params: { project_id: 'ecookbook', id: task.id }
    end
    assert_response :success
    assert_select 'input#periodictask_subject[value=?]', 'Weekly backup'
    assert_select 'input#periodictask_interval_number[value=?]', '3'
    assert_select 'select#periodictask_interval_units option[value=week][selected=selected]'
    assert_select 'textarea#periodictask_description', text: 'Run the backup'
    assert_select 'input#periodictask_id[value]', 0 # a copy is a new record
  end

  def test_index_links_to_the_copy_action
    task = create_test_periodictask
    get :index, params: { project_id: 'ecookbook' }
    assert_select 'a[href=?]', copy_periodictask_path(project_id: 'ecookbook', id: task.id)
  end

  def test_denies_member_without_permission
    # dlopez (user 3) is a Developer member of ecookbook but the Developer role
    # was not granted the :periodictask permission in setup.
    @request.session[:user_id] = 3
    get :index, params: { project_id: 'ecookbook' }
    assert_response 403
  end

  private

  def rendered_weekday_values
    css_select('#periodictask_weekdays_field input[type=checkbox]').map { |i| i['value'] }
  end

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
