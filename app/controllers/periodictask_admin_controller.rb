# Administration side of the plugin: the cross-project list of periodic tasks
# and the manual checker run offered on the plugin settings page.
class PeriodictaskAdminController < ApplicationController
  layout 'admin'
  self.main_menu = false

  before_action :require_admin
  accept_api_auth :index

  helper :periodictask
  helper :sort
  include SortHelper

  # Every periodic task of every project, so an administrator can see what is
  # scheduled without visiting each project in turn.
  def index
    sort_init 'next_run_date', 'asc'
    sort_update(
      'project' => "#{Project.table_name}.name",
      'next_run_date' => "#{Periodictask.table_name}.next_run_date",
      'subject' => "#{Periodictask.table_name}.subject"
    )

    @tasks = Periodictask.joins(:project)
                         .preload(:project, :tracker, :assigned_to)
                         .order(sort_clause)
    respond_to do |format|
      format.html { @last_runs = last_runs_for(@tasks) }
      format.api do
        @offset, @limit = api_offset_and_limit
        @task_count = @tasks.count
        @tasks = @tasks.offset(@offset).limit(@limit).to_a
        @last_runs = last_runs_for(@tasks)
      end
    end
  end

  # Runs the checker without waiting for cron or calling the endpoint, to
  # verify a scheduler setup.
  def run_checker
    count = ScheduledTasksChecker.checktasks!(source: 'manual')
    flash[:notice] = l(:notice_periodictask_checker_run, count: count)
    redirect_to plugin_settings_path('periodictask')
  end

  private

  def last_runs_for(tasks)
    PeriodictaskIssue.where(periodictask_id: tasks.map(&:id)).group(:periodictask_id).maximum(:created_at)
  end
end
