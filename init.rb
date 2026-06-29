require 'redmine'

# Load the view hook listener at boot so it registers itself. Done here (not via
# an autoload reference in to_prepare) because a bare constant in void context
# does not reliably trigger autoloading.
require_relative 'lib/redmine_periodictask/hooks'

Rails.configuration.to_prepare do
  unless Project.included_modules.include? RedminePeriodictask::ProjectPatch
    Project.include RedminePeriodictask::ProjectPatch
  end
end

Redmine::Plugin.register :periodictask do
  name 'Redmine Periodictask plugin'
  author 'Julian Perelli'
  description 'Plugin to create a task periodically by defining an interval'
  version '6.1.3'
  url 'https://github.com/jperelli/Redmine-Periodic-Task/'
  author_url 'https://jperelli.com.ar/'

  project_module :periodictask do
    permission :periodictask,
               { periodictask: %i[index show new create edit update destroy customfields run_now] }
  end

  menu :project_menu, :periodictask, { controller: 'periodictask', action: 'index' },
       caption: 'Periodic Task', after: :settings, param: :project_id
end
