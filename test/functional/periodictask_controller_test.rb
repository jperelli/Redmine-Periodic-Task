require "#{File.dirname(__FILE__)}/../test_helper"

class PeriodictaskControllerTest < ActionController::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issue_categories, :issues, :versions, :attachments

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

  def test_new_does_not_require_an_assignee
    get :new, params: { project_id: 'ecookbook' }

    assert_select '#periodictask_assigned_to_id:not([required])'
    assert_select '#periodictask_assigned_to_id option[value=""]', text: "(#{I18n.t(:label_default)})"
    assert_select 'label[for="periodictask_assigned_to_id"] span.required', count: 0
    assert_select 'a.assign-to-me-link'
  end

  def test_create_periodictask_without_assignee
    assert_difference('Periodictask.count') do
      post :create, params: {
        project_id: 'ecookbook',
        periodictask: {
          subject: 'Unassigned periodic task',
          tracker_id: 1,
          assigned_to_id: '',
          interval_number: 1,
          interval_units: 'month',
          next_run_date: 1.month.from_now.to_s
        }
      }
    end
    assert_redirected_to controller: 'periodictask', action: 'index', project_id: 'ecookbook'

    task = Periodictask.order(:id).last
    assert_equal 'Unassigned periodic task', task.subject
    assert_nil task.assigned_to_id
  end

  def test_update_can_clear_the_assignee
    task = create_test_periodictask
    patch :update, params: {
      project_id: 'ecookbook',
      id: task.id,
      periodictask: { assigned_to_id: '' }
    }
    assert_redirected_to controller: 'periodictask', action: 'index', project_id: 'ecookbook'
    assert_nil task.reload.assigned_to_id
  end

  def test_index_and_show_display_default_for_task_without_assignee
    task = create_test_periodictask(subject: 'Unassigned task', assigned_to_id: nil)

    get :index, params: { project_id: 'ecookbook' }
    assert_response :success

    get :show, params: { project_id: 'ecookbook', id: task.id }
    assert_response :success
    assert_select '.periodictask-template .attributes .assigned-to .value', text: /\A\(#{I18n.t(:label_default)}\)/
    assert_select '.periodictask-template .attributes .assigned-to .value span.icon-help[title=?]',
                  I18n.t(:label_assigned_to_info)
  end

  def test_run_now_without_assignee_applies_category_default_assignee
    category = IssueCategory.create!(project: @project, name: 'Ops', assigned_to_id: 3)
    task = create_test_periodictask(subject: 'Unassigned run', assigned_to_id: nil, issue_category_id: category.id)

    assert_difference('Issue.count') do
      post :run_now, params: { project_id: 'ecookbook', id: task.id }
    end
    assert_equal 3, Issue.where(subject: 'Unassigned run').last.assigned_to_id
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

  def test_edit_lists_project_categories_and_selects_the_configured_one
    task = create_test_periodictask(issue_category_id: 2)

    get :edit, params: { project_id: 'ecookbook', id: task.id }

    assert_select '#periodictask_issue_category_id' do
      assert_select 'option[value="1"]', text: 'Printing'
      assert_select 'option[selected="selected"][value="2"]', text: 'Recipes'
      assert_select 'option[value="3"]', 0
      assert_select 'optgroup', 0
    end
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

  def test_show_links_to_the_issue_list_filtered_by_the_task
    task = create_test_periodictask
    get :show, params: { project_id: 'ecookbook', id: task.id }
    assert_response :success
    assert_select 'a.periodictask-all-issues[href=?]',
                  "/projects/ecookbook/issues?periodictask=#{task.id}&set_filter=1&status_id=%2A",
                  text: /All issues generated by this task/
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

  def test_relation_to_previous_issue_round_trips_through_the_form
    post :create, params: {
      project_id: 'ecookbook',
      periodictask: {
        subject: 'Chained', tracker_id: 1, assigned_to_id: 2, author_id: 2,
        interval_number: 1, interval_units: 'week',
        relations: { '0' => { relation_type: 'follows', target: 'previous_issue', issue_id: '', delay: '1' },
                     '1' => { relation_type: 'relates', target: 'issue', issue_id: '1', delay: '' } }
      }
    }
    assert_response :redirect
    task = Periodictask.find_by(subject: 'Chained')
    assert_equal [{ 'relation_type' => 'follows', 'issue_id' => 'previous_issue', 'delay' => '1' },
                  { 'relation_type' => 'relates', 'issue_id' => '1', 'delay' => nil }], task.relations

    get :edit, params: { project_id: 'ecookbook', id: task.id }
    assert_response :success
    assert_select 'select[name=?] option[selected][value=follows]', 'periodictask[relations][0][relation_type]'
    assert_select 'select[name=?] option[selected][value=previous_issue]', 'periodictask[relations][0][target]'
    assert_select 'input[name=?][value]', 'periodictask[relations][0][issue_id]', count: 0
    assert_select 'select[name=?] option[selected][value=issue]', 'periodictask[relations][1][target]'
    assert_select 'input[name=?][value="1"]', 'periodictask[relations][1][issue_id]'

    patch :update, params: {
      project_id: 'ecookbook', id: task.id,
      periodictask: {
        relations: { '0' => { relation_type: 'follows', target: 'previous_issue', issue_id: '', delay: '1' },
                     '1' => { relation_type: 'relates', target: 'issue', issue_id: '1', delay: '' } }
      }
    }
    assert_response :redirect
    assert_equal task.relations, task.reload.relations

    get :show, params: { project_id: 'ecookbook', id: task.id }
    assert_response :success
    assert_select '.periodictask-relations li',
                  text: /#{I18n.t(:label_follows)}.*#{I18n.t(:label_relation_previous_issue)}/m
  end

  def test_run_now_twice_relates_the_new_issue_to_the_previous_one
    task = create_test_periodictask(next_run_date: 1.month.from_now, subject: 'Weekly **PREVIOUS_ISSUE**',
                                    relations: [{ 'relation_type' => 'relates', 'issue_id' => 'previous_issue' }])
    assert_no_difference('IssueRelation.count') do
      post :run_now, params: { project_id: 'ecookbook', id: task.id }
    end
    first = task.created_issues.first
    assert_equal 'Weekly ', first.subject
    assert_nil task.reload.last_error

    assert_difference('IssueRelation.count', 1) do
      post :run_now, params: { project_id: 'ecookbook', id: task.id }
    end
    second = task.created_issues.where.not(id: first.id).first
    assert_equal "Weekly ##{first.id}", second.subject
    assert_equal [first], second.relations.map { |r| r.other_issue(second) }.to_a
    assert_nil task.reload.last_error
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

  def test_new_renders_weekend_adjustment_select_with_none_selected
    get :new, params: { project_id: 'ecookbook' }
    assert_response :success
    assert_select 'select#periodictask_weekend_adjustment' do
      assert_select 'option', count: 3
      assert_select 'option[value=none][selected=selected]', text: 'Run on that day'
      assert_select 'option[value=next_working_day]', text: 'Move to the next working day'
      assert_select 'option[value=previous_working_day]', text: 'Move to the previous working day'
    end
  end

  def test_create_stores_weekend_adjustment_for_any_unit
    assert_difference('Periodictask.count') do
      post :create, params: {
        project_id: 'ecookbook',
        periodictask: {
          subject: 'Monthly report', tracker_id: 1, interval_number: 1, interval_units: 'month',
          weekend_adjustment: 'previous_working_day', next_run_date: '2026-08-01T10:00'
        }
      }
    end
    task = Periodictask.order(:id).last
    assert_equal 'previous_working_day', task.weekend_adjustment

    patch :update, params: { project_id: 'ecookbook', id: task.id, periodictask: { interval_units: 'day' } }
    assert_equal 'previous_working_day', task.reload.weekend_adjustment

    patch :update, params: { project_id: 'ecookbook', id: task.id, periodictask: { weekend_adjustment: 'bogus' } }
    assert_equal 'none', task.reload.weekend_adjustment
  end

  def test_edit_and_copy_select_the_persisted_weekend_adjustment
    task = create_test_periodictask(weekend_adjustment: 'next_working_day')

    get :edit, params: { project_id: 'ecookbook', id: task.id }
    assert_response :success
    assert_select 'select#periodictask_weekend_adjustment option[value=next_working_day][selected=selected]'

    get :copy, params: { project_id: 'ecookbook', id: task.id }
    assert_response :success
    assert_select 'select#periodictask_weekend_adjustment option[value=next_working_day][selected=selected]'
  end

  def test_index_and_show_describe_weekend_adjustment_and_moved_run
    task = create_test_periodictask(subject: 'Moved', interval_units: 'month', weekend_adjustment: 'next_working_day',
                                    next_run_date: Time.utc(2026, 8, 1, 10, 0)) # Saturday
    plain = create_test_periodictask(subject: 'Plain', interval_units: 'month',
                                     next_run_date: Time.utc(2026, 8, 1, 10, 0))
    User.find(2).pref.update!(time_zone: 'UTC')
    expected = 'each month on day 1, non-working days moved to the next working day'

    get :index, params: { project_id: 'ecookbook' }
    assert_select 'td.interval', text: expected
    assert_select 'td.interval', text: 'each month on day 1'
    assert_select 'td span[title=?]', Time.utc(2026, 8, 3, 10, 0).iso8601, count: 1
    assert_select 'td span[title=?]', Time.utc(2026, 8, 1, 10, 0).iso8601, count: 1
    assert_select 'td .periodictask-moved-from', text: '(moved from 08/01/2026 10:00 AM)', count: 1

    get :show, params: { project_id: 'ecookbook', id: task.id }
    assert_select '.interval .value', text: expected
    assert_select '.weekend-adjustment .value', text: 'Move to the next working day'
    assert_select '.next-run-date .value span[title=?]', Time.utc(2026, 8, 3, 10, 0).iso8601
    assert_select '.next-run-date .value .periodictask-moved-from', text: '(moved from 08/01/2026 10:00 AM)'

    get :show, params: { project_id: 'ecookbook', id: plain.id }
    assert_select '.weekend-adjustment .value', text: 'Run on that day'
    assert_select '.next-run-date .value span[title=?]', Time.utc(2026, 8, 1, 10, 0).iso8601
    assert_select '.periodictask-moved-from', count: 0
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

  def test_new_from_issue_prefills_the_issue_template_without_saving
    # Issue 1: tracker 1, priority 4, category 1, 200h, due in 10 days, no assignee.
    issue = Issue.find(1)
    issue.update_columns(assigned_to_id: 3, fixed_version_id: 3)
    Issue.create!(project: @project, tracker_id: 1, author_id: 2, subject: 'Child',
                  status_id: 1, priority_id: 4, parent_issue_id: issue.id)
    child = Issue.find_by(subject: 'Child')

    assert_no_difference('Periodictask.count') do
      get :new, params: { project_id: 'ecookbook', from_issue_id: child.id }
    end
    assert_response :success
    assert_select 'input#periodictask_subject[value=?]', 'Child'
    assert_select 'select#periodictask_tracker_id option[value="1"][selected=selected]'
    assert_select 'select#periodictask_priority_id option[value="4"][selected=selected]'
    assert_select 'input#periodictask_parent_id[value=?]', issue.id.to_s
    assert_select 'input#periodictask_id[value]', 0

    get :new, params: { project_id: 'ecookbook', from_issue_id: issue.id }
    assert_response :success
    assert_select 'input#periodictask_subject[value=?]', 'Cannot print recipes'
    assert_select 'textarea#periodictask_description', text: 'Unable to print recipes'
    assert_select 'select#periodictask_issue_category_id option[value="1"][selected=selected]'
    assert_select 'select#periodictask_fixed_version_id option[value="3"][selected=selected]'
    assert_select 'select#periodictask_assigned_to_id option[value="3"][selected=selected]'
    assert_select 'input#periodictask_estimated_hours[value=?]', '200:00'
    assert_select 'input#periodictask_parent_id[value]', 0
  end

  def test_new_from_issue_prefills_done_ratio_custom_fields_and_watchers
    field = IssueCustomField.create!(name: 'Environment', field_format: 'string', is_for_all: true,
                                     trackers: Tracker.all)
    issue = Issue.find(2) # tracker 2, done ratio 30 %
    issue.custom_field_values = { field.id.to_s => 'staging' }
    issue.save!
    issue.add_watcher(User.find(3))

    get :new, params: { project_id: 'ecookbook', from_issue_id: issue.id }
    assert_response :success
    assert_select 'select#periodictask_done_ratio option[value="30"][selected=selected]'
    assert_select 'input[name=?][value=?]', "periodictask[custom_field_values][#{field.id}]", 'staging'
    assert_select '#watchers_inputs input[value="3"][checked=checked]'
  end

  def test_new_from_issue_keeps_recurrence_defaults_and_uses_a_future_due_date_as_first_run
    issue = Issue.find(1) # due in 10 days
    get :new, params: { project_id: 'ecookbook', from_issue_id: issue.id }
    assert_response :success
    assert_select 'input#periodictask_interval_number[value=?]', '1'
    assert_select 'select#periodictask_interval_units option[value=day][selected=selected]'
    assert_select 'input#periodictask_next_run_date[value=?]', "#{issue.due_date.strftime('%Y-%m-%d')}T00:00"
  end

  def test_new_from_issue_ignores_a_past_or_missing_due_date
    [3, 2].each do |id| # 3: due 5 days ago, 2: no due date
      get :new, params: { project_id: 'ecookbook', from_issue_id: id }
      assert_response :success
      assert_select 'input#periodictask_next_run_date[value]', 0
    end
  end

  def test_new_from_issue_does_not_copy_the_status
    issue = Issue.find(2) # status 2 (Assigned)
    get :new, params: { project_id: 'ecookbook', from_issue_id: issue.id }
    assert_select 'select#periodictask_status_id option[selected=selected]', 0
  end

  def test_new_from_issue_of_another_project_returns_404
    get :new, params: { project_id: 'ecookbook', from_issue_id: 4 } # issue 4 is on onlinestore
    assert_response :not_found
  end

  def test_new_from_unknown_issue_returns_404
    get :new, params: { project_id: 'ecookbook', from_issue_id: 999_999 }
    assert_response :not_found
  end

  def test_new_from_issue_not_visible_to_the_user_returns_404
    issue = Issue.find(1)
    issue.update_columns(is_private: true, author_id: 3, assigned_to_id: nil)
    Role.find(1).update!(issues_visibility: 'default') # own + public only

    get :new, params: { project_id: 'ecookbook', from_issue_id: issue.id }
    assert_response :not_found
  end

  def test_new_from_issue_requires_the_periodictask_permission
    Role.find(1).remove_permission!(:periodictask)
    get :new, params: { project_id: 'ecookbook', from_issue_id: 1 }
    assert_response :forbidden
  end

  def test_index_links_to_the_copy_action
    task = create_test_periodictask
    get :index, params: { project_id: 'ecookbook' }
    assert_select 'a[href=?]', copy_periodictask_path(project_id: 'ecookbook', id: task.id)
  end

  def test_new_renders_the_attachments_field
    get :new, params: { project_id: 'ecookbook' }
    assert_response :success
    assert_select 'form[enctype="multipart/form-data"] #periodictask_attachments input[type=file][name=?]',
                  'attachments[dummy][file]'
    assert_select 'input[name=copy_attachments]', 0
  end

  def test_create_with_attachment
    set_tmp_attachments_directory
    assert_difference('Periodictask.count') do
      assert_difference('Attachment.count') do
        post :create, params: {
          project_id: 'ecookbook',
          periodictask: { subject: 'With file', tracker_id: 1, assigned_to_id: 2,
                          interval_number: 1, interval_units: 'month', next_run_date: 1.month.from_now.to_s },
          attachments: { '1' => { 'file' => uploaded_test_file('testfile.txt', 'text/plain'),
                                  'description' => 'Checklist' } }
        }
      end
    end
    assert_redirected_to controller: 'periodictask', action: 'index', project_id: 'ecookbook'
    task = Periodictask.find_by(subject: 'With file')
    attachment = task.attachments.to_a.tap { |files| assert_equal 1, files.size }.first
    assert_equal 'testfile.txt', attachment.filename
    assert_equal 'Checklist', attachment.description
    assert_equal 2, attachment.author_id
    assert attachment.readable?
  end

  def test_create_with_invalid_task_keeps_the_upload_for_the_rerendered_form
    set_tmp_attachments_directory
    assert_no_difference('Periodictask.count') do
      post :create, params: {
        project_id: 'ecookbook',
        periodictask: { subject: 'Bad task', tracker_id: 1, interval_number: nil, interval_units: 'month' },
        attachments: { '1' => { 'file' => uploaded_test_file('testfile.txt', 'text/plain') } }
      }
    end
    assert_response :success
    attachment = Attachment.order(:id).last
    assert_nil attachment.container_id
    assert_select 'input[name=?][value=?]', 'attachments[p0][token]', attachment.token
  end

  def test_update_with_attachment
    set_tmp_attachments_directory
    task = create_test_periodictask
    assert_difference('Attachment.count') do
      patch :update, params: {
        project_id: 'ecookbook',
        id: task.id,
        periodictask: { subject: 'Updated subject' },
        attachments: { '1' => { 'file' => uploaded_test_file('testfile.txt', 'text/plain') } }
      }
    end
    assert_redirected_to controller: 'periodictask', action: 'index', project_id: 'ecookbook'
    task.reload
    assert_equal 'Updated subject', task.subject
    assert_equal ['testfile.txt'], task.attachments.map(&:filename)
  end

  def test_update_with_rejected_attachment_saves_the_task_and_warns
    set_tmp_attachments_directory
    task = create_test_periodictask
    with_settings attachment_extensions_denied: 'txt' do
      assert_no_difference('Attachment.count') do
        patch :update, params: {
          project_id: 'ecookbook',
          id: task.id,
          periodictask: { subject: 'Updated subject' },
          attachments: { '1' => { 'file' => uploaded_test_file('testfile.txt', 'text/plain') } }
        }
      end
    end
    assert_redirected_to controller: 'periodictask', action: 'index', project_id: 'ecookbook'
    assert_equal 'Updated subject', task.reload.subject
    assert_match(/1 file\(s\) could not be saved/, flash[:warning])
  end

  def test_show_lists_attachments_with_delete_links
    set_fixtures_attachments_directory
    task = create_test_periodictask
    attachment = Attachment.find(4).copy(container: task)
    attachment.save!

    get :show, params: { project_id: 'ecookbook', id: task.id }
    assert_response :success
    assert_select 'div.attachments' do
      assert_select 'a[href^=?]', "/attachments/#{attachment.id}", text: 'source.rb'
      assert_select 'a.delete[href=?][data-method=delete]', "/attachments/#{attachment.id}"
    end
  end

  def test_edit_lists_attachments
    set_fixtures_attachments_directory
    task = create_test_periodictask
    Attachment.find(4).copy(container: task).save!

    get :edit, params: { project_id: 'ecookbook', id: task.id }
    assert_response :success
    assert_select '#periodictask_attachments div.attachments a', text: 'source.rb'
    assert_select 'form[enctype="multipart/form-data"] #periodictask_attachments input[type=file]'
  end

  def test_attachment_of_a_task_is_visible_and_deletable_with_the_periodictask_permission
    set_fixtures_attachments_directory
    task = create_test_periodictask
    attachment = Attachment.find(4).copy(container: task)
    attachment.save!

    user = User.find(2)
    assert attachment.visible?(user)
    assert attachment.deletable?(user)

    Role.find(1).remove_permission!(:periodictask)
    user.reload
    assert_not attachment.visible?(user)
    assert_not attachment.deletable?(user)
  end

  def test_copy_form_offers_to_copy_the_attachments
    set_fixtures_attachments_directory
    task = create_test_periodictask
    Attachment.find(4).copy(container: task).save!

    get :copy, params: { project_id: 'ecookbook', id: task.id }
    assert_response :success
    assert_select 'input[type=hidden][name=copy_from][value=?]', task.id.to_s
    assert_select 'input[type=checkbox][name=copy_attachments][value="1"][checked=checked]'
  end

  def test_create_from_copy_copies_the_attachments
    set_fixtures_attachments_directory
    source = create_test_periodictask(subject: 'Source')
    Attachment.find(4).copy(container: source, description: 'Form to fill in').save!

    assert_difference('Attachment.count') do
      post :create, params: {
        project_id: 'ecookbook',
        copy_from: source.id,
        copy_attachments: '1',
        periodictask: { subject: 'Copied', tracker_id: 1, assigned_to_id: 2,
                        interval_number: 1, interval_units: 'month', next_run_date: 1.month.from_now.to_s }
      }
    end
    copy = Periodictask.find_by(subject: 'Copied')
    attachment = copy.attachments.to_a.tap { |files| assert_equal 1, files.size }.first
    assert_equal 'source.rb', attachment.filename
    assert_equal 'Form to fill in', attachment.description
    assert_equal 2, attachment.author_id
    assert_not_equal source.attachments.first.id, attachment.id
    assert_equal 1, source.attachments.count
  end

  def test_create_from_copy_without_copy_attachments_copies_nothing
    set_fixtures_attachments_directory
    source = create_test_periodictask(subject: 'Source')
    Attachment.find(4).copy(container: source).save!

    assert_no_difference('Attachment.count') do
      post :create, params: {
        project_id: 'ecookbook',
        copy_from: source.id,
        periodictask: { subject: 'Copied', tracker_id: 1, assigned_to_id: 2,
                        interval_number: 1, interval_units: 'month', next_run_date: 1.month.from_now.to_s }
      }
    end
    assert_empty Periodictask.find_by(subject: 'Copied').attachments
  end

  def test_create_from_copy_ignores_a_source_from_another_project
    set_fixtures_attachments_directory
    other = Project.find(2)
    EnabledModule.create!(project: other, name: 'periodictask')
    source = Periodictask.create!(project: other, tracker_id: 1, assigned_to_id: 2, author_id: 2,
                                  subject: 'Elsewhere', interval_number: 1, interval_units: 'month',
                                  next_run_date: 1.month.from_now)
    Attachment.find(4).copy(container: source).save!

    assert_no_difference('Attachment.count') do
      post :create, params: {
        project_id: 'ecookbook',
        copy_from: source.id,
        copy_attachments: '1',
        periodictask: { subject: 'Copied', tracker_id: 1, assigned_to_id: 2,
                        interval_number: 1, interval_units: 'month', next_run_date: 1.month.from_now.to_s }
      }
    end
    assert_empty Periodictask.find_by(subject: 'Copied').attachments
  end

  def test_run_now_copies_the_attachments_onto_the_issue
    set_fixtures_attachments_directory
    task = create_test_periodictask(next_run_date: 1.month.from_now)
    template_attachment = Attachment.find(4).copy(container: task, description: 'Checklist')
    template_attachment.save!

    assert_difference('Issue.count', 1) do
      assert_difference('Attachment.count', 1) do
        post :run_now, params: { project_id: 'ecookbook', id: task.id }
      end
    end
    assert_nil task.reload.last_error
    issue = task.created_issues.to_a.tap { |issues| assert_equal 1, issues.size }.first
    copy = issue.attachments.to_a.tap { |copies| assert_equal 1, copies.size }.first
    assert_not_equal template_attachment.id, copy.id
    assert_equal 'source.rb', copy.filename
    assert_equal 'Checklist', copy.description
    assert_equal template_attachment.author_id, copy.author_id

    issue.attachments.delete(copy)
    assert Attachment.exists?(template_attachment.id)
    assert template_attachment.reload.readable?
  end

  def test_run_now_records_attachment_copy_failures_in_last_error
    set_tmp_attachments_directory
    task = create_test_periodictask(next_run_date: 1.month.from_now)
    Attachment.find(4).copy(container: task).save! # file not present under the tmp storage path

    assert_difference('Issue.count', 1) do
      assert_no_difference('Attachment.count') do
        post :run_now, params: { project_id: 'ecookbook', id: task.id }
      end
    end
    assert_match(/source\.rb/, task.reload.last_error)
    assert_match(/source\.rb/, flash[:error])
    assert_equal 1, task.created_issues.count
  end

  def test_destroy_deletes_the_attachments
    set_fixtures_attachments_directory
    task = create_test_periodictask
    attachment = Attachment.find(4).copy(container: task)
    attachment.save!

    assert_difference('Attachment.count', -1) do
      delete :destroy, params: { project_id: 'ecookbook', id: task.id }
    end
    assert_not Attachment.exists?(attachment.id)
    assert Attachment.exists?(4) # the source record on issue 2 is untouched
  end

  def test_edit_offers_open_versions_and_keeps_the_configured_one
    # Version 1 is closed, 2 is locked, 3 is open (all on ecookbook).
    task = create_test_periodictask(fixed_version_id: 1)
    get :edit, params: { project_id: 'ecookbook', id: task.id }
    assert_response :success
    assert_select 'select#periodictask_fixed_version_id' do
      assert_select 'option[value=?]', '3'
      assert_select 'option[value=?]', '2', 0
      assert_select 'option[selected=selected][value=?]', '1'
    end
  end

  def test_create_stores_target_version_and_disabled_state
    post :create, params: {
      project_id: 'ecookbook',
      periodictask: {
        subject: 'Versioned task', tracker_id: 1, assigned_to_id: 2, author_id: 2,
        interval_number: 1, interval_units: 'month', fixed_version_id: '3', is_active: '0'
      }
    }
    assert_response :redirect

    task = Periodictask.find_by(subject: 'Versioned task')
    assert_equal 3, task.fixed_version_id
    assert_not task.is_active?
  end

  def test_run_now_works_on_a_disabled_task
    task = create_test_periodictask(is_active: false)
    assert_difference('Issue.count') do
      post :run_now, params: { project_id: 'ecookbook', id: task.id }
    end
    assert_response :redirect
  end

  def test_task_of_another_project_is_not_reachable_through_this_project
    other = create_test_periodictask(project: Project.find(2), subject: 'Onlinestore task')

    get :show, params: { project_id: 'ecookbook', id: other.id }
    assert_response 404
    get :edit, params: { project_id: 'ecookbook', id: other.id }
    assert_response 404
    get :copy, params: { project_id: 'ecookbook', id: other.id }
    assert_response 404
    patch :update, params: { project_id: 'ecookbook', id: other.id, periodictask: { subject: 'Hijacked' } }
    assert_response 404
    assert_no_difference('Issue.count') do
      post :run_now, params: { project_id: 'ecookbook', id: other.id }
    end
    assert_response 404
    assert_no_difference('Periodictask.count') do
      delete :destroy, params: { project_id: 'ecookbook', id: other.id }
    end
    assert_response 404
    assert_equal 2, other.reload.project_id
    assert_equal 'Onlinestore task', other.subject
  end

  def test_index_marks_disabled_and_failed_tasks
    create_test_periodictask(subject: 'Paused task', is_active: false)
    create_test_periodictask(subject: 'Broken task', last_error: 'Tracker cannot be blank')
    get :index, params: { project_id: 'ecookbook' }
    assert_response :success
    assert_select 'td', text: /Paused task/ do
      assert_select 'span.icon-locked[title=?]', I18n.t(:label_disabled)
      assert_select 'span.icon-locked svg' if Redmine::VERSION::MAJOR >= 6
    end
    assert_select 'td', text: /Broken task/ do
      assert_select 'span.icon-error[title=?]', 'Tracker cannot be blank'
      assert_select 'span.icon-error svg' if Redmine::VERSION::MAJOR >= 6
    end
  end

  def test_index_sorts_business_day_intervals_by_duration
    create_test_periodictask(subject: 'One week', interval_number: 1, interval_units: 'week')
    create_test_periodictask(subject: 'Three business days', interval_number: 3, interval_units: 'business_day')
    create_test_periodictask(subject: 'One day', interval_number: 1, interval_units: 'day')
    get :index, params: { project_id: 'ecookbook', sort: 'interval:asc' }
    assert_response :success
    body = @response.body
    assert_operator body.index('One day'), :<, body.index('Three business days')
    assert_operator body.index('Three business days'), :<, body.index('One week')
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
