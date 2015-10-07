class PeriodictaskController < ApplicationController
  unloadable


  before_filter :find_project
  #before_filter :find_periodictask, :except => [:new, :create, :index]
  before_filter :load_users, :except => [:destroy]
  before_filter :load_categories, :except => [:destroy]

  def index
    if !params[:project_id] then return end
    @project_identifier = params[:project_id]
    # find_all_by is considered deprecated (Rails 4)
    @tasks = Periodictask.where(project_id: @project[:id])
    #@tasks = Periodictask.find_all_by_project_id(@project[:id])
  end

  def new
    @periodictask = Periodictask.new(:project=>@project, :author_id=>User.current.id)
  end

  def create
    @periodictask = Periodictask.new(:project=>@project, :author_id=>User.current.id)
    params[:periodictask][:project_id] = @project[:id]
    @periodictask.attributes = params[:periodictask]
    if @periodictask.save
      flash[:notice] = l(:flash_task_created)
      redirect_to :controller => 'periodictask', :action => 'index', :project_id=>params[:project_id]
    end
  end

  def edit
    @periodictask = Periodictask.find(params[:id])
    @periodictask[:project_id] = @project[:identifier]
    params[:project_id] = @project[:identifier]
  end

  def update
    @periodictask = Periodictask.find(params[:id])
    params[:periodictask][:project_id] = @project[:id]
    if @periodictask.update_attributes(params[:periodictask])
      flash[:notice] = l(:flash_task_saved)
      # redirect_to :controller => 'periodictask', :action => 'index', :project_id=>params[:project_id]
      redirect_to :controller => 'periodictask', :action => 'index', :project_id=>params[:project_id]
    end
  end

  def show
  end

  def destroy
      @task = Periodictask.find(params[:id])
      @task.destroy
      redirect_to :controller => 'periodictask', :action => 'index', :project_id=>params[:project_id]
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
