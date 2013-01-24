require 'redmine'

Redmine::Plugin.register :redmine_periodictask do
  name 'Redmine Periodictask plugin'
  author 'Tanguy de Courson'
  description 'This is a plugin for Redmine that will allow you to schedule a task to be assigned on a schedule'
  version '1.0.1'

  project_module :periodictask do
    permission :periodictask, {:periodictask => [:index, :edit]}
  end

  menu :project_menu, :periodictask, { :controller => 'periodictask', :action => 'index' }, :caption => 'Periodic Task', :after => :settings, :param => :project_id
end
