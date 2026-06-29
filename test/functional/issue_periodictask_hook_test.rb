require "#{File.dirname(__FILE__)}/../test_helper"

class IssuePeriodictaskHookTest < ActionController::TestCase
  tests IssuesController

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issue_categories

  def setup
    @project = Project.find(1)
    EnabledModule.create!(project: @project, name: 'periodictask')

    role = Role.find(1) # Manager
    role.add_permission!(:periodictask) unless role.has_permission?(:periodictask)

    @request.session[:user_id] = 2 # jsmith, Manager of ecookbook
  end

  def test_shows_origin_note_for_issue_generated_by_periodictask
    task = create_task
    issue = create_issue
    task.record_generated_issue(issue)

    get :show, params: { id: issue.id }
    assert_response :success
    assert_select 'p.periodictask-origin'
    assert_select 'p.periodictask-origin a[href=?]',
                  "/projects/#{@project.identifier}/periodictask/#{task.id}",
                  text: "##{task.id}"
  end

  def test_no_note_for_regular_issue
    issue = create_issue
    get :show, params: { id: issue.id }
    assert_response :success
    assert_select 'p.periodictask-origin', count: 0
  end

  private

  def create_task
    Periodictask.create!(
      project: @project, tracker_id: 1, author_id: 2,
      subject: 'Origin task', interval_number: 1, interval_units: 'month'
    )
  end

  def create_issue
    Issue.create!(
      project: @project, tracker_id: 1, author_id: 2, subject: 'Generated issue',
      status_id: 1, priority_id: IssuePriority.default.id
    )
  end
end
