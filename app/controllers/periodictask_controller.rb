class PeriodictaskController < ApplicationController
  unloadable


  before_filter :find_project
  #before_filter :find_periodictask, :except => [:new, :create, :index]
  before_filter :load_users, :except => [:destroy]

  def index
    if !params[:project_id] then return end
    @project_identifier = params[:project_id]
    @tasks = Periodictask.find_all_by_project_id(@project[:id])
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
    # Get the users that are members in the project
    #
    #@users = User.find_by_sql('SELECT users.id, CONCAT(users.firstname, \' \', users.lastname) fullname FROM members INNER JOIN users
    #  ON members.user_id = users.id
    #  WHERE project_id = ' + @project[:id].to_s + '
    #  AND status = 1
    #  ORDER BY firstname ASC')
    @users = []
    @project.members.each do |m|
      @users << m.user
    end

  end
end
