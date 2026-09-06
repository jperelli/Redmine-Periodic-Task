require "#{File.dirname(__FILE__)}/../test_helper"

# Form, detail page and copy of the if_previous_open setting.
class PeriodictaskIfPreviousOpenControllerTest < ActionController::TestCase
  tests PeriodictaskController

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issue_categories, :issues, :versions, :workflows

  def setup
    @project = Project.find(1)
    EnabledModule.create!(project: @project, name: 'periodictask')
    role = Role.find(1)
    role.add_permission!(:periodictask) unless role.has_permission?(:periodictask)
    @request.session[:user_id] = 2
  end

  def create_task(attrs = {})
    Periodictask.create!({ project: @project, tracker_id: 1, assigned_to_id: 2, author_id: 2,
                           subject: 'Weekly report', interval_number: 1, interval_units: 'week',
                           next_run_date: 1.week.from_now }.merge(attrs))
  end

  def test_new_form_offers_every_mode_with_create_preselected_and_a_help_link
    get :new, params: { project_id: 'ecookbook' }
    assert_response :success

    assert_select 'p.periodictask-if-previous-open label span[title=?]', I18n.t(:label_if_previous_open_info),
                  text: I18n.t(:label_if_previous_open)
    assert_select "select#periodictask_if_previous_open[name='periodictask[if_previous_open]']" do
      Periodictask::IF_PREVIOUS_OPEN_MODES.each do |mode|
        assert_select "option[value=#{mode}]", text: I18n.t(:"label_if_previous_open_#{mode}")
      end
      assert_select 'option[selected=selected][value=create]'
      assert_select 'option[selected=selected]', 1
    end
    assert_select 'p.periodictask-if-previous-open em.info', 0
    assert_select 'p.periodictask-if-previous-open a.icon-help[href=?][title=?]',
                  RedminePeriodictask::IF_PREVIOUS_OPEN_DOC_URL, I18n.t(:label_if_previous_open_help)
    assert_select 'p.periodictask-credit a[href=?]', RedminePeriodictask::RECURRENCE_DOC_URL, 0
  end

  def test_create_persists_the_selected_mode
    assert_difference('Periodictask.count') do
      post :create, params: {
        project_id: 'ecookbook',
        periodictask: { subject: 'Weekly report', tracker_id: 1, assigned_to_id: 2, interval_number: 1,
                        interval_units: 'week', if_previous_open: 'close_previous' }
      }
    end
    assert_equal 'close_previous', Periodictask.last.if_previous_open
  end

  def test_create_rejects_an_unknown_mode
    assert_no_difference('Periodictask.count') do
      post :create, params: {
        project_id: 'ecookbook',
        periodictask: { subject: 'Weekly report', tracker_id: 1, assigned_to_id: 2, interval_number: 1,
                        interval_units: 'week', if_previous_open: 'delete_everything' }
      }
    end
    assert_response :success
    assert_select '#errorExplanation'
  end

  def test_update_changes_the_mode
    task = create_task
    patch :update, params: { project_id: 'ecookbook', id: task.id,
                             periodictask: { if_previous_open: 'after_completion' } }
    assert_response :redirect
    assert_equal 'after_completion', task.reload.if_previous_open
  end

  def test_edit_form_preselects_the_saved_mode
    task = create_task(if_previous_open: 'skip')
    get :edit, params: { project_id: 'ecookbook', id: task.id }
    assert_response :success
    assert_select 'select#periodictask_if_previous_open option[selected=selected][value=skip]'
    assert_select 'select#periodictask_if_previous_open option[selected=selected]', 1
  end

  def test_show_displays_the_mode
    task = create_task(if_previous_open: 'after_completion')
    get :show, params: { project_id: 'ecookbook', id: task.id }
    assert_response :success
    assert_select '.periodictask-schedule .if-previous-open .label', text: "#{I18n.t(:label_if_previous_open)}:"
    assert_select '.periodictask-schedule .if-previous-open .value span[title=?]',
                  I18n.t(:label_if_previous_open_after_completion_info),
                  text: I18n.t(:label_if_previous_open_after_completion)
    assert_select 'p.periodictask-last-skipped', 0
  end

  def test_show_displays_the_last_skipped_run_above_the_generated_issues
    task = create_task(if_previous_open: 'skip', next_run_date: 1.hour.ago)
    ScheduledTasksChecker.checktasks!
    first = task.reload.last_generated_issue
    task.update_columns(next_run_date: 1.hour.ago)
    ScheduledTasksChecker.checktasks!
    assert_equal first.id, task.reload.last_skipped_issue_id

    get :show, params: { project_id: 'ecookbook', id: task.id }
    assert_response :success
    assert_select 'p.periodictask-last-skipped' do
      assert_select 'a[href=?]', "/issues/#{first.id}", text: /##{first.id}/
      assert_select 'span.icon-time'
    end
    assert_select 'p.periodictask-last-skipped', text: /was still open/
    assert_select ".periodictask-generated-issues tr#issue-#{first.id}"
  end

  def test_run_now_always_creates_an_issue_whatever_the_mode
    task = create_task(if_previous_open: 'skip', next_run_date: 1.hour.ago)
    ScheduledTasksChecker.checktasks!
    assert_difference('Issue.count') do
      post :run_now, params: { project_id: 'ecookbook', id: task.id }
    end
    assert_response :redirect
    assert_equal 2, task.created_issues.count
  end

  def test_copy_prefills_the_mode_of_the_source_task
    task = create_task(if_previous_open: 'close_previous')
    get :copy, params: { project_id: 'ecookbook', id: task.id }
    assert_response :success
    assert_select 'select#periodictask_if_previous_open option[selected=selected][value=close_previous]'
    assert_select 'select#periodictask_if_previous_open option[selected=selected]', 1
  end
end
