require 'redmine'

Redmine::Plugin.register :periodictask do
  name 'Redmine Periodic task plugin'
  author 'yoshiaki tanaka'
  description 'This is a plugin for Redmine that will allow you to schedule a task to be assigned on a schedule'
  version '4.0'
  url 'https://github.com/wate/redmine_periodic_task'
  project_module :periodictask do
    permission :periodictask, {:periodictask => [:index, :edit]}
  end
  menu :project_menu, :periodictask, { :controller => 'periodictask', :action => 'index' }, caption: :project_menu_periodictask, after: :settings, param: :project_id

end
