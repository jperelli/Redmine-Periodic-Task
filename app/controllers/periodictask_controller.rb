class PeriodictaskController < ApplicationController
  unless respond_to?(:before_action)
    class << self
      alias before_action before_filter
    end
  end

  before_action :find_project
  # before_filter :find_periodictask, :except => [:new, :create, :index]
  before_action :load_users, except: [:destroy]
  before_action :load_categories, except: [:destroy]
  before_action :load_watchers, except: [:destroy]

  helper :custom_fields
  include CustomFieldsHelper

  def index
    return unless params[:project_id]

    @project_identifier = params[:project_id]
    @tasks = Periodictask.where(project_id: @project[:id])
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
      flash[:notice] = l(:flash_task_saved)
      redirect_to controller: 'periodictask', action: 'index', project_id: params[:project_id]
    else
      render action: 'edit'
    end
  end

  def show; end

  def destroy
    @task = Periodictask.accessible.find(params[:id])
    @task.destroy
    redirect_to controller: 'periodictask', action: 'index', project_id: params[:project_id]
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
    @authors = []
    @project.members.each do |m|
      @authors << m.user
    end
  end

  def load_categories
    # Get the issue categories
    @categories = @project.issue_categories
  end

  def load_watchers
    @watchers = []
    @project.members.each do |m|
      @watchers << m.user
    end
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
