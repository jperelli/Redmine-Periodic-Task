require "#{File.dirname(__FILE__)}/../test_helper"

# Issue list (HTML and REST API) with the "Periodic task" filter, column and
# recurrence marker.
class IssuesPeriodictaskFilterTest < ActionController::TestCase
  tests IssuesController

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issue_categories, :issues, :versions, :queries

  def setup
    @project = Project.find(1)
    EnabledModule.create!(project: @project, name: 'periodictask')
    Role.find(1).add_permission!(:periodictask) # Manager
    @request.session[:user_id] = 2 # jsmith, Manager of ecookbook

    @task = create_task('Backup check')
    @generated = create_issue('Backup check 2026-09')
    @task.record_generated_issue(@generated)
    @manual = create_issue('Written by hand')
  end

  def test_index_with_short_filter_lists_only_the_issues_of_the_task
    get :index, params: { project_id: @project.identifier, set_filter: 1, periodictask: @task.id }
    assert_response :success
    assert_select "tr#issue-#{@generated.id}"
    assert_select "tr#issue-#{@manual.id}", count: 0
    assert_select 'tr#issue-1', count: 0
  end

  def test_index_with_none_operator_hides_the_generated_issues
    get :index, params: { project_id: @project.identifier, set_filter: 1,
                          f: ['periodictask'], op: { periodictask: '!*' } }
    assert_response :success
    assert_select "tr#issue-#{@generated.id}", count: 0
    assert_select "tr#issue-#{@manual.id}"
  end

  def test_global_index_with_any_operator
    get :index, params: { set_filter: 1, periodictask: '*' }
    assert_response :success
    assert_select "tr#issue-#{@generated.id}"
    assert_select "tr#issue-#{@manual.id}", count: 0
  end

  def test_index_offers_the_filter_with_the_project_tasks
    get :index, params: { project_id: @project.identifier, set_filter: 1 }
    assert_response :success
    assert_select 'select#add_filter_select option[value=periodictask]', text: 'Periodic task'
    assert_select 'select#available_c option[value=periodictask]', text: 'Periodic task'
    assert_select 'select#group_by option[value=periodictask]', text: 'Periodic task'
  end

  def test_index_marks_generated_issues_in_the_subject_cell
    get :index, params: { project_id: @project.identifier, set_filter: 1 }
    assert_response :success
    assert_select "tr#issue-#{@generated.id} td.subject span.periodictask-generated[title=?]",
                  "Automatically created by periodic task ##{@task.id}"
    marker = "tr#issue-#{@generated.id} td.subject span.periodictask-generated"
    assert_select "#{marker} + a", text: @generated.subject
    assert_select "#{marker} svg.s14" if Redmine::VERSION::MAJOR >= 6
    assert_select "tr#issue-#{@manual.id} td.subject span.periodictask-generated", count: 0
  end

  def test_index_periodictask_column_links_to_the_task
    get :index, params: { project_id: @project.identifier, set_filter: 1, c: %w[subject periodictask] }
    assert_response :success
    assert_select 'table.list.issues th', text: 'Periodic task'
    assert_select "tr#issue-#{@generated.id} td.periodictask a[href=?]",
                  "/projects/#{@project.identifier}/periodictask/#{@task.id}", text: 'Backup check'
    assert_select "tr#issue-#{@manual.id} td.periodictask", text: ''
  end

  def test_index_periodictask_column_without_permission_shows_the_subject_unlinked
    Role.find(1).remove_permission!(:periodictask)
    get :index, params: { project_id: @project.identifier, set_filter: 1, c: %w[subject periodictask] }
    assert_response :success
    assert_select "tr#issue-#{@generated.id} td.periodictask", text: 'Backup check'
    assert_select "tr#issue-#{@generated.id} td.periodictask a", count: 0
  end

  def test_index_grouped_by_periodictask
    get :index, params: { project_id: @project.identifier, set_filter: 1, group_by: 'periodictask' }
    assert_response :success
    assert_select 'tr.group', text: /Backup check/
    assert_select "tr#issue-#{@generated.id}"
  end

  def test_index_sorted_by_periodictask
    get :index, params: { project_id: @project.identifier, set_filter: 1, sort: 'periodictask:desc' }
    assert_response :success
    assert_select "tr#issue-#{@generated.id}"
  end

  def test_index_csv_with_periodictask_column
    get :index, params: { project_id: @project.identifier, set_filter: 1, c: %w[subject periodictask],
                          periodictask: @task.id, format: 'csv' }
    assert_response :success
    assert_include 'Backup check 2026-09', @response.body
    assert_include ",Backup check\n", @response.body.tr("\r", '')
  end

  def test_api_index_with_periodictask_filter
    with_settings rest_api_enabled: '1' do
      get :index, params: { format: 'json', set_filter: 1, periodictask: @task.id, key: User.find(2).api_key }
    end
    assert_response :success
    json = ActiveSupport::JSON.decode(@response.body)
    assert_equal [@generated.id], json['issues'].pluck('id')
    assert_equal 1, json['total_count']
  end

  def test_api_index_with_none_operator
    with_settings rest_api_enabled: '1' do
      get :index, params: { format: 'json', project_id: @project.identifier, set_filter: 1,
                            periodictask: '!*', key: User.find(2).api_key }
    end
    assert_response :success
    ids = ActiveSupport::JSON.decode(@response.body)['issues'].pluck('id')
    assert_not_includes ids, @generated.id
    assert_includes ids, @manual.id
  end

  private

  def create_task(subject)
    Periodictask.create!(
      project: @project, tracker_id: 1, author_id: 2, subject: subject,
      interval_number: 1, interval_units: 'month'
    )
  end

  def create_issue(subject)
    Issue.create!(
      project: @project, tracker_id: 1, author_id: 2, subject: subject,
      status_id: 1, priority_id: IssuePriority.default.id
    )
  end
end
