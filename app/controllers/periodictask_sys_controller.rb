# Runs the periodic task checker on demand, for cron-less setups that call
# this URL from an external scheduler (uptime monitor, CI cron, Windows Task
# Scheduler...). Protected the same way as Redmine's /sys API:
# Administration -> Settings -> Repositories -> "Enable WS for repository
# management" and its API key, passed as ?key=.
class PeriodictaskSysController < ActionController::Base
  before_action :check_enabled

  def check
    count = ScheduledTasksChecker.checktasks!
    render plain: "Periodictask: #{count} task(s) run", status: :ok
  end

  private

  def check_enabled
    User.current = nil
    return if Setting.sys_api_enabled? && params[:key].to_s == Setting.sys_api_key

    render plain: 'Access denied. Repository management WS is disabled or key is invalid.', status: :forbidden
  end
end
