require "#{File.dirname(__FILE__)}/../test_helper"

# "Periodic task" filter and column of IssueQuery (lib/redmine_periodictask/issue_query_patch.rb).
class IssueQueryPeriodictaskTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issue_categories, :issues, :versions, :queries

  def setup
    @project = Project.find(1)
    @subproject = Project.find(3) # child of project 1
    @other_project = Project.find(2) # jsmith is Developer there, without the permission
    [@project, @subproject, @other_project].each do |p|
      EnabledModule.create!(project: p, name: 'periodictask')
    end
    Role.find(1).add_permission!(:periodictask) # Manager
    Member.create!(project: @subproject, user: User.find(2), roles: [Role.find(1)])
    User.current = User.find(2) # jsmith

    @task = create_task(@project, 'Backup check')
    @subtask = create_task(@subproject, 'Archive rotation')
    @other_task = create_task(@other_project, 'Store inventory')

    @generated = create_issue(@project, 'Backup check 2026-09')
    @task.record_generated_issue(@generated)
    @sub_generated = create_issue(@subproject, 'Archive rotation 2026-09')
    @subtask.record_generated_issue(@sub_generated)
    @manual = create_issue(@project, 'Written by hand')
  end

  def teardown
    User.current = nil
  end

  def test_filter_is_available_on_project_and_global_queries
    assert IssueQuery.new(project: @project).available_filters.key?('periodictask')
    assert IssueQuery.new.available_filters.key?('periodictask')
    assert_equal :list_optional, IssueQuery.new.available_filters['periodictask'][:type]
    assert_equal 'Periodic task', IssueQuery.new.available_filters['periodictask'][:name]
  end

  def test_filter_values_list_the_tasks_of_the_project_and_its_subprojects
    values = IssueQuery.new(project: @project).available_filters['periodictask'][:values]
    assert_equal [['Backup check', @task.id.to_s, @project.name],
                  ['Archive rotation', @subtask.id.to_s, @subproject.name]], values
  end

  def test_filter_values_list_every_visible_task_on_the_global_query
    ids = IssueQuery.new.available_filters['periodictask'][:values].map { |v| v[1].to_i }
    assert_includes ids, @task.id
    assert_includes ids, @subtask.id
    assert_not_includes ids, @other_task.id, 'tasks of projects without the permission are hidden'

    Role.find(2).add_permission!(:periodictask) # Developer
    User.current = User.find(2) # drop the memoized projects_by_role
    ids = IssueQuery.new.available_filters['periodictask'][:values].map { |v| v[1].to_i }
    assert_includes ids, @other_task.id
  end

  def test_filter_values_hide_tasks_of_projects_where_the_module_is_disabled
    EnabledModule.where(project_id: @subproject.id, name: 'periodictask').delete_all
    ids = IssueQuery.new(project: @project).available_filters['periodictask'][:values].map { |v| v[1].to_i }
    assert_equal [@task.id], ids
  end

  def test_any_operator_lists_the_issues_generated_by_any_task
    ids = issue_ids(project_query('*', ['']))
    assert_includes ids, @generated.id
    assert_includes ids, @sub_generated.id
    assert_not_includes ids, @manual.id
    assert_not_includes ids, 1
  end

  def test_none_operator_lists_the_issues_created_by_hand
    ids = issue_ids(project_query('!*', ['']))
    assert_includes ids, @manual.id
    assert_includes ids, 1
    assert_not_includes ids, @generated.id
    assert_not_includes ids, @sub_generated.id
  end

  def test_is_operator_lists_the_issues_of_the_selected_tasks
    assert_equal [@generated.id], issue_ids(project_query('=', [@task.id.to_s]))
    assert_equal [@sub_generated.id, @generated.id].sort,
                 issue_ids(project_query('=', [@task.id.to_s, @subtask.id.to_s])).sort
  end

  def test_is_not_operator_excludes_the_issues_of_the_selected_tasks
    ids = issue_ids(project_query('!', [@task.id.to_s]))
    assert_not_includes ids, @generated.id
    assert_includes ids, @sub_generated.id
    assert_includes ids, @manual.id
  end

  def test_is_operator_without_a_valid_task_matches_nothing
    assert_equal [], issue_ids(project_query('=', ['abc']))
    assert_equal [], issue_ids(project_query('=', [(@task.id + 1000).to_s]))
  end

  def test_is_operator_requires_a_value
    query = project_query('=', [''])
    assert_not query.valid?
    assert_includes query.errors.full_messages.join, 'Periodic task'
  end

  def test_filter_works_on_the_global_query
    query = IssueQuery.new(name: '_')
    query.filters = { 'periodictask' => { operator: '=', values: [@subtask.id.to_s] } }
    assert_equal [@sub_generated.id], issue_ids(query)
  end

  def test_filter_survives_a_saved_query
    query = IssueQuery.new(name: 'Generated issues', project: @project, user: User.find(2),
                           visibility: Query::VISIBILITY_PRIVATE)
    query.filters = { 'periodictask' => { operator: '=', values: [@task.id.to_s] } }
    assert query.save, query.errors.full_messages.join(', ')

    reloaded = IssueQuery.find(query.id)
    assert_equal({ operator: '=', values: [@task.id.to_s] }, reloaded.filters['periodictask'].symbolize_keys)
    assert_equal [@generated.id], issue_ids(reloaded)
    assert_equal 1, reloaded.issue_count
  end

  def test_column_is_available_and_optional
    query = IssueQuery.new(project: @project)
    column = query.available_columns.detect { |c| c.name == :periodictask }
    assert column
    assert_equal 'Periodic task', column.caption
    assert_not query.has_column?(:periodictask)
    assert column.sortable.present?
    assert column.groupable?
    assert_equal 1, query.available_columns.map(&:name).count(:periodictask)
  end

  def test_column_value_is_the_generating_task
    column = IssueQuery.new.available_columns.detect { |c| c.name == :periodictask }
    assert_equal @task, column.value_object(@generated)
    assert_nil column.value_object(@manual)
    assert_equal 'Backup check', @task.to_s
  end

  def test_issues_preload_the_generating_task_without_extra_queries
    query = project_query('*', [''])
    query.column_names = %i[subject periodictask]
    issues = query.issues

    count = count_queries do
      issues.each { |issue| [issue.periodictask_issue, issue.periodictask] }
    end
    assert_equal 0, count
    assert_equal @task, issues.detect { |i| i.id == @generated.id }.periodictask
    assert_equal @subtask, issues.detect { |i| i.id == @sub_generated.id }.periodictask
  end

  def test_issues_preload_the_join_row_for_the_marker_without_the_column
    query = IssueQuery.new(name: '_', project: @project)
    query.filters = {}
    query.column_names = %i[subject]
    issues = query.issues

    count = count_queries do
      issues.each(&:periodictask_issue)
    end
    assert_equal 0, count
    assert_equal @task.id, issues.detect { |i| i.id == @generated.id }.periodictask_issue.periodictask_id
    assert_nil issues.detect { |i| i.id == @manual.id }.periodictask_issue
  end

  def test_sort_by_periodictask
    query = project_query('*', [''])
    query.sort_criteria = [%w[periodictask asc]]
    assert_equal [@sub_generated.id, @generated.id], issue_ids(query) # Archive < Backup
    query.sort_criteria = [%w[periodictask desc]]
    assert_equal [@generated.id, @sub_generated.id], issue_ids(query)
  end

  def test_group_by_periodictask
    query = IssueQuery.new(name: '_', project: @project)
    query.filters = {}
    query.group_by = 'periodictask'
    assert query.grouped?

    counts = query.result_count_by_group
    assert_equal 1, counts[@task]
    assert_equal 1, counts[@subtask]
    assert_operator counts[nil], :>=, 1

    issues = query.issues
    assert_equal @task, query.group_by_column.group_value(issues.detect { |i| i.id == @generated.id })
    assert_nil query.group_by_column.group_value(issues.detect { |i| i.id == @manual.id })
  end

  def test_visible_scope_and_predicate
    assert_includes Periodictask.visible.to_a, @task
    assert_includes Periodictask.visible.to_a, @subtask
    assert_not_includes Periodictask.visible.to_a, @other_task
    assert @task.visible?
    assert_not @other_task.visible?
    assert @other_task.visible?(User.find(1))
  end

  private

  def project_query(operator, values)
    query = IssueQuery.new(name: '_', project: @project)
    query.filters = { 'periodictask' => { operator: operator, values: values } }
    query
  end

  def issue_ids(query)
    query.issues.map(&:id)
  end

  def count_queries(&)
    count = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
    end
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
    count
  end

  def create_task(project, subject)
    Periodictask.create!(
      project: project, tracker_id: 1, author_id: 2, subject: subject,
      interval_number: 1, interval_units: 'month'
    )
  end

  def create_issue(project, subject)
    Issue.create!(
      project: project, tracker_id: 1, author_id: 2, subject: subject,
      status_id: 1, priority_id: IssuePriority.default.id
    )
  end
end
