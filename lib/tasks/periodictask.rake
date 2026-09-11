desc <<~END_DESC
  Check for and assign periodic tasks

  Example:
    rake redmine:check_periodictasks RAILS_ENV="production"
END_DESC

Rails.configuration.active_job.queue_adapter = :inline if Rails.configuration.respond_to?(:active_job)

namespace :redmine do
  task check_periodictasks: :environment do
    # Redmine loads every plugins/*/lib/tasks/*.rake under Rails.root, but
    # only registers the plugins found in its plugins directory, which can be
    # elsewhere (Debian packages: /var/lib/redmine/<instance>/plugins).
    unless Redmine::Plugin.installed?(:periodictask)
      abort <<~MSG
        The periodictask plugin is not loaded by this Redmine.
        Its rake task was found under #{Rails.root.join('plugins')}, but Redmine loads plugins from
        #{Redmine::PluginLoader.directory}. Move or symlink the plugin there and restart Redmine.
        See https://github.com/jperelli/Redmine-Periodic-Task#installation
      MSG
    end

    ScheduledTasksChecker.checktasks!
  end
end
