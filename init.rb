require 'redmine'

Rails.configuration.to_prepare do
  unless Project.included_modules.include? RedminePeriodictask::ProjectPatch
    Project.include RedminePeriodictask::ProjectPatch
  end
end

Redmine::Plugin.register :periodictask do
  name 'Redmine Periodictask plugin'
  author 'Julian Perelli'
  description 'Plugin to create a task periodically by defining an interval'
  version '6.1.1'
  url 'https://github.com/jperelli/Redmine-Periodic-Task/'
  author_url 'https://jperelli.com.ar/'

  project_module :periodictask do
    permission :periodictask, { periodictask: %i[index edit] }
  end

  menu :project_menu, :periodictask, { controller: 'periodictask', action: 'index' },
       caption: 'Periodic Task', after: :settings, param: :project_id
end
