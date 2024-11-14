require 'redmine'

Rails.configuration.to_prepare do
  unless Project.included_modules.include? RedminePeriodictask::ProjectPatch
    Project.send(:include, RedminePeriodictask::ProjectPatch)
  end
end

Redmine::Plugin.register :periodictask do
  name 'Redmine Periodictask plugin'
  author 'Julian Perelli'
  description 'Plugin to create a task periodically by defining an interval, forked and updated for Redmine 6'
  version '6.0.0'
  url 'https://github.com/tuzumkuru/Redmine-Periodic-Task'

  project_module :periodictask do
    permission :periodictask, {:periodictask => [:index, :edit]}
  end

  menu :project_menu, :periodictask, { :controller => 'periodictask', :action => 'index' }, :caption => 'Periodic Task', :after => :settings, :param => :project_id
end
