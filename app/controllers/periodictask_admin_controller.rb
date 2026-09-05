# Lets an administrator run the checker from the plugin settings page, to
# verify a scheduler setup without waiting for cron or calling the endpoint.
class PeriodictaskAdminController < ApplicationController
  layout 'admin'
  before_action :require_admin

  def run_checker
    count = ScheduledTasksChecker.checktasks!(source: 'manual')
    flash[:notice] = l(:notice_periodictask_checker_run, count: count)
    redirect_to plugin_settings_path('periodictask')
  end
end
