require 'redmine'

# Load the view hook listener at boot so it registers itself. Done here (not via
# an autoload reference in to_prepare) because a bare constant in void context
# does not reliably trigger autoloading.
require_relative 'lib/redmine_periodictask/hooks'

module RedminePeriodictask
  # Explains how next run dates are calculated; linked from the form and the
  # last-error display.
  RECURRENCE_DOC_URL = 'https://github.com/jperelli/Redmine-Periodic-Task/blob/main/doc/recurrence-design.md'.freeze
end

Rails.configuration.to_prepare do
  unless Project.included_modules.include? RedminePeriodictask::ProjectPatch
    Project.include RedminePeriodictask::ProjectPatch
  end
end

Redmine::Plugin.register :periodictask do
  name 'Redmine Periodictask plugin'
  author 'Julian Perelli'
  description 'Plugin to create a task periodically by defining an interval'
  version '7.0.0'
  url 'https://github.com/jperelli/Redmine-Periodic-Task/'
  author_url 'https://jperelli.com.ar/'

  project_module :periodictask do
    permission :periodictask,
               { periodictask: %i[index show new create edit update destroy customfields run_now tags] }
  end

  # Surface create/update/delete of periodic tasks in the activity log, gated by
  # the :periodictask permission (see PeriodictaskJournal).
  activity_provider :periodictasks, class_name: 'PeriodictaskJournal'

  menu :project_menu, :periodictask, { controller: 'periodictask', action: 'index' },
       caption: :label_periodic_tasks, after: :settings, param: :project_id
end
