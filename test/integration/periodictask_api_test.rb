require "#{File.dirname(__FILE__)}/../test_helper"

# REST API (JSON + XML) for the project-scoped periodic tasks and the admin list.
class PeriodictaskApiTest < Redmine::ApiTest::Base
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issue_categories, :issues, :versions, :tokens,
           :custom_fields, :custom_fields_projects, :custom_fields_trackers

  def setup
    super
    @project = Project.find(1) # ecookbook
    @other_project = Project.find(2) # onlinestore
    EnabledModule.create!(project: @project, name: 'periodictask')
    EnabledModule.create!(project: @other_project, name: 'periodictask')

    Role.find(1).add_permission!(:periodictask) # Manager: jsmith on ecookbook
    Role.find(2).remove_permission!(:periodictask) # Developer: dlopper on ecookbook
  end

  # --- index ---------------------------------------------------------------

  def test_index_json
    task = create_test_periodictask(subject: 'Weekly report', interval_number: 1, interval_units: 'week',
                                    weekdays: [1, 3])
    issue = Issue.find(1)
    PeriodictaskIssue.create!(periodictask: task, issue: issue, created_at: Time.zone.parse('2026-01-05 08:00:00'))

    get '/projects/ecookbook/periodictask.json', headers: api_headers
    assert_response :success
    assert_equal 'application/json', @response.media_type

    json = ActiveSupport::JSON.decode(@response.body)
    assert_equal 1, json['total_count']
    assert_equal 0, json['offset']
    assert_equal 25, json['limit']
    t = json['periodictasks'].first
    assert_equal task.id, t['id']
    assert_equal 'Weekly report', t['subject']
    assert_equal({ 'id' => 1, 'name' => 'eCookbook' }, t['project'])
    assert_equal({ 'id' => 1, 'name' => 'Bug' }, t['tracker'])
    assert_equal({ 'id' => 2, 'name' => 'John Smith' }, t['author'])
    assert_equal({ 'id' => 2, 'name' => 'John Smith' }, t['assigned_to'])
    assert_equal 1, t['interval_number']
    assert_equal 'week', t['interval_units']
    assert_equal [1, 3], t['weekdays']
    assert_equal true, t['is_active']
    assert_equal task.next_run_date.xmlschema(0), t['next_run_date']
    assert_equal '2026-01-05T08:00:00Z', t['last_run']
    assert_nil t['last_error']
    assert_not t.key?('issues'), 'generated issues are only listed with include=issues'
  end

  def test_index_xml
    create_test_periodictask(subject: 'XML listed')

    get '/projects/ecookbook/periodictask.xml', headers: api_headers
    assert_response :success
    assert_equal 'application/xml', @response.media_type
    assert_select 'periodictasks[type=array][total_count="1"][limit="25"][offset="0"]' do
      assert_select 'periodictask' do
        assert_select 'subject', text: 'XML listed'
        assert_select 'project[id="1"][name=eCookbook]'
        assert_select 'author[id="2"]'
        assert_select 'is_active', text: 'true'
      end
    end
  end

  def test_index_pagination
    3.times { |i| create_test_periodictask(subject: "Task #{i}") }

    get '/projects/ecookbook/periodictask.json', params: { limit: 2, offset: 1, sort: 'id' }, headers: api_headers
    assert_response :success
    json = ActiveSupport::JSON.decode(@response.body)
    assert_equal 3, json['total_count']
    assert_equal 1, json['offset']
    assert_equal 2, json['limit']
    assert_equal(['Task 1', 'Task 2'], json['periodictasks'].map { |t| t['subject'] })
  end

  def test_index_include_issues
    task = create_test_periodictask
    PeriodictaskIssue.create!(periodictask: task, issue: Issue.find(1))
    PeriodictaskIssue.create!(periodictask: task, issue: Issue.find(2))

    get '/projects/ecookbook/periodictask.json', params: { include: 'issues' }, headers: api_headers
    assert_response :success
    json = ActiveSupport::JSON.decode(@response.body)
    assert_equal [1, 2], json['periodictasks'].first['issues'].map { |i| i['id'] }.sort
  end

  def test_index_only_lists_tasks_of_the_project
    create_test_periodictask(subject: 'Mine')
    create_test_periodictask(project: @other_project, subject: 'Theirs')

    get '/projects/ecookbook/periodictask.json', headers: api_headers
    json = ActiveSupport::JSON.decode(@response.body)
    assert_equal(['Mine'], json['periodictasks'].map { |t| t['subject'] })
  end

  # --- show ----------------------------------------------------------------

  def test_show_json
    task = create_test_periodictask(
      subject: 'Full task', description: 'Body', interval_number: 2, interval_units: 'month',
      monthly_mode: 'weekday', weekdays: [5], month_weeks: [1, 3], set_start_date: true,
      due_date_number: 3, due_date_units: 'day', estimated_hours: 1.5, done_ratio: 20,
      issue_category_id: 1, fixed_version_id: 2, priority_id: 6, status_id: 2,
      watcher_user_ids: [3], rotation_ids: [3, 2], custom_field_values: { '1' => 'MySQL' },
      subtasks: [{ 'tracker_id' => '2', 'subject' => 'Sub', 'assigned_to_id' => '3', 'estimated_hours' => '2' }],
      relations: [{ 'relation_type' => 'follows', 'issue_id' => '1', 'delay' => '2' }],
      last_error: 'boom', is_active: false
    )

    get "/projects/ecookbook/periodictask/#{task.id}.json", headers: api_headers
    assert_response :success
    t = ActiveSupport::JSON.decode(@response.body)['periodictask']
    assert_equal task.id, t['id']
    assert_equal 'Full task', t['subject']
    assert_equal 'Body', t['description']
    assert_equal 2, t['interval_number']
    assert_equal 'month', t['interval_units']
    assert_equal 'weekday', t['monthly_mode']
    assert_equal [5], t['weekdays']
    assert_equal [1, 3], t['month_weeks']
    assert_equal true, t['set_start_date']
    assert_equal 3, t['due_date_number']
    assert_equal 'day', t['due_date_units']
    assert_equal 1.5, t['estimated_hours']
    assert_equal 20, t['done_ratio']
    assert_equal({ 'id' => 1, 'name' => 'Printing' }, t['category'])
    assert_equal({ 'id' => 2, 'name' => '1.0' }, t['fixed_version'])
    assert_equal({ 'id' => 6, 'name' => 'High' }, t['priority'])
    assert_equal({ 'id' => 2, 'name' => 'Assigned' }, t['status'])
    assert_equal [{ 'id' => 3, 'name' => 'Dave Lopper' }], t['watchers']
    assert_equal [{ 'id' => 3, 'name' => 'Dave Lopper' }, { 'id' => 2, 'name' => 'John Smith' }], t['rotation']
    assert_equal({ 'id' => 3, 'name' => 'Dave Lopper' }, t['rotation_next'])
    assert_equal [{ 'id' => 1, 'name' => 'Database', 'value' => 'MySQL' }], t['custom_fields']
    assert_equal [{ 'tracker_id' => '2', 'subject' => 'Sub', 'assigned_to_id' => '3', 'estimated_hours' => 2.0 }],
                 t['subtasks']
    assert_equal [{ 'relation_type' => 'follows', 'issue_id' => '1', 'delay' => '2' }], t['relations']
    assert_equal 'boom', t['last_error']
    assert_equal false, t['is_active']
    assert_nil t['last_run']
    assert t.key?('created_at')
    assert t.key?('updated_at')
    assert_not t.key?('issues')
  end

  def test_show_xml
    task = create_test_periodictask(subject: 'XML task', weekdays: [1, 2], interval_units: 'week')

    get "/projects/ecookbook/periodictask/#{task.id}.xml", headers: api_headers
    assert_response :success
    assert_equal 'application/xml', @response.media_type
    assert_select 'periodictask' do
      assert_select 'id', text: task.id.to_s
      assert_select 'subject', text: 'XML task'
      assert_select 'tracker[id="1"][name=Bug]'
      assert_select 'weekdays[type=array] weekday', count: 2
    end
  end

  def test_show_include_issues
    task = create_test_periodictask
    PeriodictaskIssue.create!(periodictask: task, issue: Issue.find(3))

    get "/projects/ecookbook/periodictask/#{task.id}.json", params: { include: 'issues' }, headers: api_headers
    assert_response :success
    issues = ActiveSupport::JSON.decode(@response.body)['periodictask']['issues']
    assert_equal([3], issues.map { |i| i['id'] })
    assert issues.first.key?('created_at')

    get "/projects/ecookbook/periodictask/#{task.id}.xml", params: { include: 'issues' }, headers: api_headers
    assert_response :success
    assert_select 'periodictask issues[type=array] issue id', text: '3'
  end

  # --- create --------------------------------------------------------------

  def test_create_json
    payload = {
      periodictask: {
        subject: 'Created via API', tracker_id: 1, assigned_to_id: 3, interval_number: 1,
        interval_units: 'week', weekdays: [1, 5], next_run_date: '2030-01-06T09:00:00Z',
        priority_id: 6, status_id: 2, issue_category_id: 1, fixed_version_id: 3, estimated_hours: 2.5,
        done_ratio: 10, watcher_user_ids: [3], custom_fields: [{ id: 1, value: 'PostgreSQL' }],
        subtasks: [{ subject: 'Child', tracker_id: 2 }],
        relations: [{ relation_type: 'relates', issue_id: 1 }],
        is_active: false
      }
    }
    assert_difference('Periodictask.count') do
      assert_no_difference('Issue.count') do
        post '/projects/ecookbook/periodictask.json', params: payload.to_json, headers: json_headers
      end
    end
    assert_response :created
    assert_equal 'application/json', @response.media_type

    task = Periodictask.order(:id).last
    assert_equal @project, task.project
    assert_equal 2, task.author_id
    assert_equal 'Created via API', task.subject
    assert_equal [1, 5], task.weekdays
    assert_equal Time.utc(2030, 1, 6, 9), task.next_run_date
    assert_equal 6, task.priority_id
    assert_equal 2, task.status_id
    assert_equal 1, task.issue_category_id
    assert_equal 3, task.fixed_version_id
    assert_equal 2.5, task.estimated_hours
    assert_equal 10, task.done_ratio
    assert_equal [3], task.watcher_user_ids
    assert_equal({ '1' => 'PostgreSQL' }, task.custom_field_values)
    assert_equal 1, task.subtasks.size
    assert_equal 'Child', task.subtasks.first['subject']
    assert_equal '2', task.subtasks.first['tracker_id'].to_s
    assert_equal 'relates', task.relations.first['relation_type']
    assert_equal '1', task.relations.first['issue_id'].to_s
    assert_equal false, task.is_active

    assert_equal periodictask_url(@project, task), @response.headers['Location']
    json = ActiveSupport::JSON.decode(@response.body)['periodictask']
    assert_equal task.id, json['id']
    assert_equal [{ 'id' => 1, 'name' => 'Database', 'value' => 'PostgreSQL' }], json['custom_fields']
  end

  def test_create_with_custom_field_values_hash
    payload = { periodictask: { subject: 'CF hash', tracker_id: 1, assigned_to_id: 2,
                                custom_field_values: { '1' => 'MySQL' } } }
    post '/projects/ecookbook/periodictask.json', params: payload.to_json, headers: json_headers
    assert_response :created
    assert_equal({ '1' => 'MySQL' }, Periodictask.order(:id).last.custom_field_values)
  end

  def test_create_json_computes_first_run_when_next_run_date_is_blank
    payload = { periodictask: { subject: 'Auto scheduled', tracker_id: 1, assigned_to_id: 2,
                                interval_number: 1, interval_units: 'day' } }
    post '/projects/ecookbook/periodictask.json', params: payload.to_json, headers: json_headers
    assert_response :created
    task = Periodictask.order(:id).last
    assert_not_nil task.next_run_date
    assert_in_delta Time.current, task.next_run_date, 1.day
  end

  def test_create_xml
    xml = <<~XML
      <?xml version="1.0"?>
      <periodictask>
        <subject>Created via XML</subject>
        <tracker_id>1</tracker_id>
        <assigned_to_id>2</assigned_to_id>
        <interval_number>2</interval_number>
        <interval_units>week</interval_units>
        <weekdays type="array"><weekday>2</weekday><weekday>4</weekday></weekdays>
        <next_run_date>2030-01-07T09:00:00Z</next_run_date>
      </periodictask>
    XML
    assert_difference('Periodictask.count') do
      post '/projects/ecookbook/periodictask.xml', params: xml, headers: xml_headers
    end
    assert_response :created
    assert_equal 'application/xml', @response.media_type
    task = Periodictask.order(:id).last
    assert_equal 'Created via XML', task.subject
    assert_equal 2, task.interval_number
    assert_equal [2, 4], task.weekdays
    assert_select 'periodictask id', text: task.id.to_s
    assert_select 'periodictask subject', text: 'Created via XML'
  end

  def test_create_json_with_validation_errors
    payload = { periodictask: { subject: '', tracker_id: 1, assigned_to_id: 2, interval_number: 0 } }
    assert_no_difference('Periodictask.count') do
      post '/projects/ecookbook/periodictask.json', params: payload.to_json, headers: json_headers
    end
    assert_response :unprocessable_entity
    json = ActiveSupport::JSON.decode(@response.body)
    assert_kind_of Array, json['errors']
    assert_includes json['errors'], 'Subject cannot be blank'
    assert(json['errors'].any? { |e| e.start_with?('Interval number') })
  end

  def test_create_xml_with_validation_errors
    xml = '<periodictask><subject></subject><tracker_id>1</tracker_id><assigned_to_id>2</assigned_to_id></periodictask>'
    assert_no_difference('Periodictask.count') do
      post '/projects/ecookbook/periodictask.xml', params: xml, headers: xml_headers
    end
    assert_response :unprocessable_entity
    assert_equal 'application/xml', @response.media_type
    assert_select 'errors[type=array] error', text: 'Subject cannot be blank'
  end

  # --- update --------------------------------------------------------------

  def test_update_json_is_partial
    task = create_test_periodictask(interval_units: 'week', weekdays: [1, 3],
                                    subtasks: [{ 'subject' => 'Keep me' }])

    put "/projects/ecookbook/periodictask/#{task.id}.json",
        params: { periodictask: { subject: 'Renamed', is_active: false } }.to_json, headers: json_headers
    assert_response :no_content
    assert_equal '', @response.body

    task.reload
    assert_equal 'Renamed', task.subject
    assert_equal false, task.is_active
    assert_equal [1, 3], task.weekdays, 'attributes that are not sent are left unchanged'
    assert_equal 'Keep me', task.subtasks.first['subject']
  end

  def test_update_json_replaces_sent_arrays
    task = create_test_periodictask(interval_units: 'week', weekdays: [1, 3])

    patch "/projects/ecookbook/periodictask/#{task.id}.json",
          params: { periodictask: { weekdays: [] } }.to_json, headers: json_headers
    assert_response :no_content
    assert_equal [], task.reload.weekdays
  end

  def test_update_xml
    task = create_test_periodictask
    put "/projects/ecookbook/periodictask/#{task.id}.xml",
        params: '<periodictask><subject>XML renamed</subject><interval_number>3</interval_number></periodictask>',
        headers: xml_headers
    assert_response :no_content
    assert_equal 'XML renamed', task.reload.subject
    assert_equal 3, task.interval_number
  end

  def test_update_json_with_validation_errors
    task = create_test_periodictask(subject: 'Unchanged')
    put "/projects/ecookbook/periodictask/#{task.id}.json",
        params: { periodictask: { subject: '' } }.to_json, headers: json_headers
    assert_response :unprocessable_entity
    assert_includes ActiveSupport::JSON.decode(@response.body)['errors'], 'Subject cannot be blank'
    assert_equal 'Unchanged', task.reload.subject
  end

  def test_update_cannot_move_task_to_another_project
    task = create_test_periodictask
    put "/projects/ecookbook/periodictask/#{task.id}.json",
        params: { periodictask: { project_id: @other_project.id } }.to_json, headers: json_headers
    assert_response :no_content
    assert_equal @project.id, task.reload.project_id
  end

  # --- destroy -------------------------------------------------------------

  def test_destroy_json
    task = create_test_periodictask
    assert_difference('Periodictask.count', -1) do
      delete "/projects/ecookbook/periodictask/#{task.id}.json", headers: api_headers
    end
    assert_response :no_content
  end

  def test_destroy_xml
    task = create_test_periodictask
    assert_difference('Periodictask.count', -1) do
      delete "/projects/ecookbook/periodictask/#{task.id}.xml", headers: api_headers
    end
    assert_response :no_content
  end

  # --- run_now -------------------------------------------------------------

  def test_run_now_json
    task = create_test_periodictask(subject: 'Run me')
    assert_difference('Issue.count') do
      assert_difference('PeriodictaskIssue.count') do
        post "/projects/ecookbook/periodictask/#{task.id}/run_now.json", headers: api_headers
      end
    end
    assert_response :created
    assert_equal 'application/json', @response.media_type
    issue = Issue.order(:id).last
    assert_equal 'Run me', issue.subject
    json = ActiveSupport::JSON.decode(@response.body)['issue']
    assert_equal issue.id, json['id']
    assert_equal 'Run me', json['subject']
    assert_equal({ 'id' => 1, 'name' => 'eCookbook' }, json['project'])
    assert_equal [], json['errors']
    assert_equal issue_url(issue), @response.headers['Location']
  end

  def test_run_now_xml
    task = create_test_periodictask
    assert_difference('Issue.count') do
      post "/projects/ecookbook/periodictask/#{task.id}/run_now.xml", headers: api_headers
    end
    assert_response :created
    assert_equal 'application/xml', @response.media_type
    assert_select 'issue id', text: Issue.order(:id).last.id.to_s
  end

  def test_run_now_reports_generation_errors
    task = create_test_periodictask
    task.update_column(:subject, '')
    assert_no_difference('Issue.count') do
      post "/projects/ecookbook/periodictask/#{task.id}/run_now.json", headers: api_headers
    end
    assert_response :unprocessable_entity
    assert_includes ActiveSupport::JSON.decode(@response.body)['errors'], 'Subject cannot be blank'
    assert_equal 'Subject cannot be blank', task.reload.last_error
  end

  # --- authentication & authorization -------------------------------------

  def test_api_key_as_parameter
    create_test_periodictask
    get '/projects/ecookbook/periodictask.json', params: { key: User.find(2).api_key }
    assert_response :success
    assert_equal 1, ActiveSupport::JSON.decode(@response.body)['total_count']
  end

  def test_requires_authentication
    task = create_test_periodictask
    get '/projects/ecookbook/periodictask.json'
    assert_response :unauthorized
    get "/projects/ecookbook/periodictask/#{task.id}.xml"
    assert_response :unauthorized
    assert_no_difference('Periodictask.count') do
      post '/projects/ecookbook/periodictask.json', params: { periodictask: { subject: 'x' } }.to_json,
                                                    headers: { 'CONTENT_TYPE' => 'application/json' }
      assert_response :unauthorized
      delete "/projects/ecookbook/periodictask/#{task.id}.json"
      assert_response :unauthorized
    end
    assert_no_difference('Issue.count') do
      post "/projects/ecookbook/periodictask/#{task.id}/run_now.json"
      assert_response :unauthorized
    end
  end

  def test_rest_api_disabled
    Setting.rest_api_enabled = '0'
    task = create_test_periodictask
    get '/projects/ecookbook/periodictask.json', headers: api_headers
    assert_response :forbidden # the API key is ignored, so the request is anonymous
    assert_no_difference('Periodictask.count') do
      delete "/projects/ecookbook/periodictask/#{task.id}.json", headers: api_headers
    end
    assert_response :forbidden
  end

  def test_forbidden_without_permission
    task = create_test_periodictask
    headers = api_headers(User.find(3)) # dlopper: Developer, no :periodictask permission
    json_headers = headers.merge('CONTENT_TYPE' => 'application/json')
    body = { periodictask: { subject: 'x' } }.to_json

    get '/projects/ecookbook/periodictask.json', headers: headers
    assert_response :forbidden
    get "/projects/ecookbook/periodictask/#{task.id}.json", headers: headers
    assert_response :forbidden
    assert_no_difference('Periodictask.count') do
      post '/projects/ecookbook/periodictask.json', params: body, headers: json_headers
      assert_response :forbidden
      put "/projects/ecookbook/periodictask/#{task.id}.json", params: body, headers: json_headers
      assert_response :forbidden
      delete "/projects/ecookbook/periodictask/#{task.id}.json", headers: headers
      assert_response :forbidden
    end
    assert_no_difference('Issue.count') do
      post "/projects/ecookbook/periodictask/#{task.id}/run_now.json", headers: headers
      assert_response :forbidden
    end
    assert_equal 'Test task', task.reload.subject
  end

  def test_forbidden_when_module_disabled
    EnabledModule.where(project: @project, name: 'periodictask').delete_all
    get '/projects/ecookbook/periodictask.json', headers: api_headers
    assert_response :forbidden
  end

  def test_task_of_another_project_is_not_reachable
    other = create_test_periodictask(project: @other_project, subject: 'Onlinestore task')

    get "/projects/ecookbook/periodictask/#{other.id}.json", headers: api_headers
    assert_response :not_found
    get "/projects/ecookbook/periodictask/#{other.id}.xml", headers: api_headers
    assert_response :not_found
    put "/projects/ecookbook/periodictask/#{other.id}.json",
        params: { periodictask: { subject: 'Hijacked' } }.to_json, headers: json_headers
    assert_response :not_found
    assert_no_difference('Issue.count') do
      post "/projects/ecookbook/periodictask/#{other.id}/run_now.json", headers: api_headers
      assert_response :not_found
    end
    assert_no_difference('Periodictask.count') do
      delete "/projects/ecookbook/periodictask/#{other.id}.json", headers: api_headers
      assert_response :not_found
    end
    assert_equal 2, other.reload.project_id
    assert_equal 'Onlinestore task', other.subject
  end

  def test_unknown_project
    get '/projects/does-not-exist/periodictask.json', headers: api_headers
    assert_response :not_found
  end

  def test_static_routes_are_not_shadowed_by_the_format_routes
    log_user('jsmith', 'jsmith')
    get '/projects/ecookbook/periodictask/new'
    assert_response :success
    assert_equal 'text/html', @response.media_type
    get '/projects/ecookbook/periodictask/tags', params: { term: 'a' }
    assert_response :success
    assert_equal 'application/json', @response.media_type
    get '/projects/ecookbook/periodictask'
    assert_response :success
    assert_equal 'text/html', @response.media_type
  end

  # --- admin list ----------------------------------------------------------

  def test_admin_index_json
    create_test_periodictask(subject: 'Mine')
    create_test_periodictask(project: @other_project, subject: 'Theirs')

    get '/admin/periodictasks.json', params: { limit: 1 }, headers: api_headers(User.find(1))
    assert_response :success
    json = ActiveSupport::JSON.decode(@response.body)
    assert_equal 2, json['total_count']
    assert_equal 1, json['limit']
    assert_equal 1, json['periodictasks'].size
    assert json['periodictasks'].first.key?('project')

    get '/admin/periodictasks.xml', headers: api_headers(User.find(1))
    assert_response :success
    assert_select 'periodictasks[type=array][total_count="2"] periodictask', count: 2
  end

  def test_admin_index_is_admin_only
    get '/admin/periodictasks.json', headers: api_headers
    assert_response :forbidden
    get '/admin/periodictasks.json'
    assert_response :unauthorized
  end

  private

  def api_headers(user = User.find(2))
    { 'X-Redmine-API-Key' => user.api_key }
  end

  def json_headers(user = User.find(2))
    api_headers(user).merge('CONTENT_TYPE' => 'application/json')
  end

  def xml_headers(user = User.find(2))
    api_headers(user).merge('CONTENT_TYPE' => 'application/xml')
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
