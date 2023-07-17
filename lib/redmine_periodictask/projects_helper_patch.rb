# frozen_string_literal: true

require_dependency 'projects_helper'

module RedminePeriodictask
  module ProjectsHelperPatch
    def self.included(base)
      base.send(:include, InstanceMethods)
      base.class_eval do
        alias_method(:project_settings_tabs_without_periodictask, :project_settings_tabs)
        alias_method(:project_settings_tabs, :project_settings_tabs_with_periodictask)
      end
    end

    module InstanceMethods
      def project_settings_tabs_with_periodictask
        tabs = project_settings_tabs_without_periodictask
        if User.current.allowed_to?(:periodictask, @project, :global => false)
          tabs << {
            name: 'periodictask',
            partial: 'periodictask/index',
            label: :label_periodic_tasks
          }
        end
        tabs
      end
    end
  end
end

# rubocop:disable Style/IfUnlessModifier
unless ProjectsHelper.included_modules.include?(RedminePeriodictask::ProjectsHelperPatch)
  ProjectsHelper.send(:include, RedminePeriodictask::ProjectsHelperPatch)
end
# rubocop:enable Style/IfUnlessModifier
