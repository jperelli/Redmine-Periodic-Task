require 'redmine'

Redmine::Plugin.register :periodictask do
  name 'Redmine Periodictask plugin'
  author 'rk team '
  description 'Plugin to create a task periodically by defining an interval'
  version '4.1.0'
  url 'https://redmine-kanban.com'
  author_url 'https://redmine-kanban.com'

  project_module :periodictask do
    permission :periodictask, {:periodictask => [:index, :edit]}
  end

  menu :project_menu, :periodictask, { :controller => 'periodictask', :action => 'index' }, :caption => :label_periodic_tasks, :after => :settings, :param => :project_id
end
