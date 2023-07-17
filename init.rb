require 'redmine'

Redmine::Plugin.register :periodictask do
  name 'Periodictask plugin'
  author 'rk team '
  description 'Plugin to create a task periodically by defining an interval'
  version '4.2.1'
  url 'https://redmine-kanban.com'
  author_url 'https://redmine-kanban.com'

  project_module :periodictask do
    permission :periodictask, {:periodictask => [:index, :edit]}
  end

  #menu :project_menu, :periodictask, { :controller => 'periodictask', :action => 'index' }, :caption => :label_periodic_tasks, :after => :settings, :param => :project_id


  settings :default => {:empty => true}, :partial => 'settings/periodictask/index'
end

require "#{File.dirname(__FILE__)}/lib/redmine_periodictask/projects_helper_patch"
require "#{File.dirname(__FILE__)}/lib/redmine_periodictask/project_patch"