class PeriodictasksAdminController < ApplicationController
  layout 'admin'
  self.main_menu = false

  before_action :require_admin

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
    @last_runs = PeriodictaskIssue.where(periodictask_id: @tasks.map(&:id))
                                  .group(:periodictask_id).maximum(:created_at)
  end
end
