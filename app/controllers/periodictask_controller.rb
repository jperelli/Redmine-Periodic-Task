class PeriodictaskController < ApplicationController
  unloadable

  class << self
    alias_method :before_action, :before_filter
  end unless respond_to?(:before_action)
  before_action :find_project
  #before_filter :find_periodictask, :except => [:new, :create, :index]
  before_action :load_users, :except => [:destroy]
  before_action :load_categories, :except => [:destroy]

  helper :custom_fields
  include CustomFieldsHelper

  def index
    if !params[:project_id] then return end
    @project_identifier = params[:project_id]
    # find_all_by is considered deprecated (Rails 4)
    @tasks = Periodictask.where(project_id: @project[:id])
    #@tasks = Periodictask.find_all_by_project_id(@project[:id])
  end

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
      redirect_to :controller => 'periodictask', :action => 'index', :project_id=>params[:project_id]
    else
      render :action => 'new'
    end
  end

  def edit
    @periodictask = Periodictask.find(params[:id])
    @periodictask.project = @project
    params[:project_id] = @project[:identifier]
    @issue = @periodictask.generate_issue
  end

  def update
    @periodictask = Periodictask.find(params[:id])
    params[:periodictask][:project_id] = @project[:id]
    @periodictask.attributes = params[:periodictask]
    @issue = @periodictask.generate_issue
    if @issue.valid? && @periodictask.save
      flash[:notice] = l(:flash_task_saved)
      # redirect_to :controller => 'periodictask', :action => 'index', :project_id=>params[:project_id]
      redirect_to :controller => 'periodictask', :action => 'index', :project_id=>params[:project_id]
    else
      render :action => 'edit'
    end
  end

  def show
  end

  def destroy
      @task = Periodictask.find(params[:id])
      @task.destroy
      redirect_to :controller => 'periodictask', :action => 'index', :project_id=>params[:project_id]
  end

  def customfields
      @periodictask = params[:periodictask][:id].present? ? Periodictask.find(params[:periodictask][:id]) : Periodictask.new(:project=>@project, :author_id=>User.current.id)
      @periodictask.attributes = params[:periodictask]
      @issue = @periodictask.generate_issue
  end

private

  def find_periodictask
    @periodictask = Periodictask.find(params[:id])
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

end
