class PeriodictaskController < ApplicationController
  unloadable

  before_action :find_project_by_project_id, :load_users
  before_action :load_categories, :except => [:destroy]
  before_action :load_versions, :except => [:destroy]

  helper :custom_fields
  include CustomFieldsHelper

  # def index
  #   Time.zone = User.current.time_zone
  #   if !params[:project_id] then return end
  #   @project_identifier = params[:project_id]
  #   @tasks = Periodictask.where(project_id: @project[:id])
  # end

  def new
    @periodictask = Periodictask.new(:project=>@project, :author_id=>User.current.id)
    @periodictask.interval_number = 1
    @issue = @periodictask.generate_issue
  end

  def create
    @periodictask = Periodictask.new(:project=>@project, :author_id=>User.current.id)
    params[:periodictask][:project_id] = @project[:id]
    @periodictask.attributes = params[:periodictask]
    @issue = @periodictask.generate_issue
    if @issue.valid? && @periodictask.save
      flash[:notice] = l(:flash_task_created)
      redirect_to settings_project_path(@project, :tab => 'periodictask')

    else
      render :action => 'new'
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
    @periodictask.attributes = params[:periodictask]
    @issue = @periodictask.generate_issue
    if @issue.valid? && @periodictask.save
      flash[:notice] = l(:flash_task_saved)
      redirect_to settings_project_path(@project, :tab => 'periodictask')
    else
      render :action => 'edit'
    end
  end

  def show
  end

  def destroy
      @task = Periodictask.accessible.find(params[:id])
      @task.destroy
      flash[:notice] = l(:flash_task_removed)
      redirect_to settings_project_path(@project, tab: 'periodictask', id: @project.id)
  end

  def customfields
      @periodictask = params[:periodictask][:id].present? ? Periodictask.accessible.find(params[:periodictask][:id]) : Periodictask.new(:project=>@project, :author_id=>User.current.id)
      @periodictask.attributes = params[:periodictask]
      @issue = @periodictask.generate_issue
  end

private

  def find_periodictask
    @periodictask = Periodictask.accessible.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end


  def load_versions
    # Get the project versions
    @versions = @project.shared_versions
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

end
