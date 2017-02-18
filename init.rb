require 'redmine'

Redmine::Plugin.register :periodictask do
  name 'Redmine Periodictask plugin'
  author 'Julian Perelli based on work from Tanguy de Courson'
  description 'This is a plugin for Redmine2 and 3 that will allow you to schedule a task to be assigned on a schedule'
  version '3.2.1'
  url 'http://github.com/jperelli/Redmine-Periodic-Task/'
  author_url 'http://jperelli.com.ar/'

  project_module :periodictask do
    permission :periodictask, {:periodictask => [:index, :edit]}
  end

  menu :project_menu, :periodictask, { :controller => 'periodictask', :action => 'index' }, :caption => 'Periodic Task', :after => :settings, :param => :project_id
end
