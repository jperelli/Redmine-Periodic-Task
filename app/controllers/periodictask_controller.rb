class PeriodictaskController < ApplicationController
  unless respond_to?(:before_action)
    class << self
      alias before_action before_filter
    end
  end

  before_action :find_project
  before_action :authorize
  # before_filter :find_periodictask, :except => [:new, :create, :index]
  before_action :load_users, except: %i[destroy run_now]
  before_action :load_categories, except: %i[destroy run_now]

  helper :custom_fields
  include CustomFieldsHelper
  helper :issues
  helper :watchers
  helper :queries
  helper :sort
  include SortHelper

  def index
    return unless params[:project_id]

    @project_identifier = params[:project_id]

    # Correlated subquery for the most recent generated-issue time, so the list
    # can be ordered by "last run" even though it isn't a column on the table.
    last_run_sql = "(SELECT MAX(#{PeriodictaskIssue.table_name}.created_at) " \
                   "FROM #{PeriodictaskIssue.table_name} " \
                   "WHERE #{PeriodictaskIssue.table_name}.periodictask_id = #{Periodictask.table_name}.id)"

    # Approximate interval length in days, so the interval column sorts by actual
    # duration (1 week > 1 day) instead of just the raw number.
    interval_days_sql = "#{Periodictask.table_name}.interval_number * " \
                        "CASE #{Periodictask.table_name}.interval_units " \
                        "WHEN 'week' THEN 7 " \
                        "WHEN 'month' THEN 30 " \
                        "WHEN 'year' THEN 365 " \
                        "ELSE 1 END"

    sort_init 'id', 'desc'
    sort_update(
      'id'            => "#{Periodictask.table_name}.id",
      'interval'      => interval_days_sql,
      'next_run_date' => "#{Periodictask.table_name}.next_run_date",
      'tracker'       => "#{Tracker.table_name}.position",
      'priority'      => "#{Periodictask.table_name}.priority_id",
      'subject'       => "#{Periodictask.table_name}.subject",
      'assigned_to'   => ["#{User.table_name}.lastname", "#{User.table_name}.firstname"],
      'last_run'      => last_run_sql
    )

    @tasks = Periodictask.where(project_id: @project[:id])
                         .left_outer_joins(:tracker, :assigned_to)
                         .preload(:tracker, :assigned_to)
                         .order(sort_clause)
    @priorities = IssuePriority.all.index_by(&:id)
    @last_runs = PeriodictaskIssue.where(periodictask_id: @tasks.map(&:id))
                                  .group(:periodictask_id).maximum(:created_at)
  end

  def new
    @periodictask = Periodictask.new(project: @project, author_id: User.current.id)
    @periodictask.interval_number = 1
    @issue = @periodictask.generate_issue
  end

  def create
    @periodictask = Periodictask.new(project: @project, author_id: User.current.id)
    params[:periodictask][:project_id] = @project[:id]
    # log values
    if params[:periodictask][:next_run_date].blank?
      params[:periodictask][:next_run_date] = @periodictask.get_next_run_date(Time.current)
    end

    @periodictask.attributes = periodictask_params
    @issue = @periodictask.generate_issue
    if @issue.valid? && @periodictask.save
      @periodictask.log_activity('create')
      flash[:notice] = l(:flash_task_created)
      redirect_to controller: 'periodictask', action: 'index', project_id: params[:project_id]
    else
      render action: 'new'
    end
  end

  def edit
    @periodictask = Periodictask.accessible.find(params[:id])
    @periodictask.project = @project
    params[:project_id] = @project[:identifier]
    @issue = @periodictask.generate_issue
  end

  def update
    @periodictask = Periodictask.accessible.find(params[:id])
    params[:periodictask][:project_id] = @project[:id]
    @periodictask.attributes = periodictask_params
    @issue = @periodictask.generate_issue
    if @issue.valid? && @periodictask.save
      @periodictask.log_activity('update')
      flash[:notice] = l(:flash_task_saved)
      redirect_to controller: 'periodictask', action: 'index', project_id: params[:project_id]
    else
      render action: 'edit'
    end
  end

  def show
    @periodictask = Periodictask.accessible.find(params[:id])
    @periodictask.project = @project

    issue_ids = @periodictask.issues.pluck(:id)
    return if issue_ids.empty?

    # Render the generated issues with Redmine's own issue list, so columns,
    # sorting and styling match the project's regular issue view.
    @query = IssueQuery.new(name: '_', project: @project)
    @query.filters = {} # drop the default "open status only" filter so closed issues show too
    @query.add_filter('issue_id', '=', [issue_ids.join(',')])
    @query.sort_criteria = params[:sort] if params[:sort].present?

    @issue_count = @query.issue_count
    @issue_pages = Paginator.new @issue_count, per_page_option, params['page']
    @issues = @query.issues(offset: @issue_pages.offset, limit: @issue_pages.per_page)
  end

  def destroy
    @task = Periodictask.accessible.find(params[:id])
    @task.destroy
    @task.log_activity('delete')
    redirect_to controller: 'periodictask', action: 'index', project_id: params[:project_id]
  end

  # Generate an issue right now from the task config, without touching the
  # schedule. Handy for testing a task before its next run date arrives.
  def run_now
    @periodictask = Periodictask.accessible.find(params[:id])
    @periodictask.project = @project
    issue = @periodictask.generate_issue(Time.current)

    if issue.nil?
      @periodictask.update(last_error: l(:label_project_missing_or_closed))
      flash[:error] = l(:flash_task_run_failed, error: l(:label_project_missing_or_closed))
    elsif issue.save
      @periodictask.log_activity('run')
      @periodictask.fill_watchers(issue)
      @periodictask.record_generated_issue(issue)
      @periodictask.update(last_error: nil)
      flash[:notice] = l(:flash_task_run_now, id: issue.id)
    else
      error = issue.errors.full_messages.join(', ')
      @periodictask.update(last_error: error)
      flash[:error] = l(:flash_task_run_failed, error: error)
    end

    # Return to wherever the action was triggered (the task detail page shows the
    # new issue in its history), falling back to the list.
    redirect_back fallback_location: { controller: 'periodictask', action: 'index', project_id: params[:project_id] }
  end

  def customfields
    @periodictask = if params[:periodictask][:id].present?
                      Periodictask.accessible.find(params[:periodictask][:id])
                    else
                      Periodictask.new(project: @project, author_id: User.current.id)
                    end
    @periodictask.attributes = periodictask_params
    @issue = @periodictask.generate_issue
  end

  private

  def find_periodictask
    @periodictask = Periodictask.accessible.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_project
    @project = Project.find(params[:project_id])
  end

  def load_users
    # Get the assignable users and groups in the project
    @assignables = @project.assignable_users

    # Get the users in the project (as authors)
    @authors = @project.members.map(&:user)
  end

  def load_categories
    # Get the issue categories
    @categories = @project.issue_categories
  end

  def periodictask_params
    params.require(:periodictask).permit(
      :project_id, :tracker_id, :assigned_to_id, :author_id, :subject,
      :interval_number, :interval_units, :next_run_date, :set_start_date,
      :due_date_number, :due_date_units, :description, :issue_category_id,
      :estimated_hours, :checklists_template_id, :parent_id, :priority_id,
      { custom_field_values: {} },
      { watcher_user_ids: [] }
    )
  end
end
