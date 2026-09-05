module RedminePeriodictask
  # Renders the "Periodic task" column (task subject linked to the task page)
  # and appends the recurrence marker to the subject cell of generated issues
  # in every issue list built with QueriesHelper#column_content.
  module QueriesHelperPatch
    include PeriodictaskHelper

    def column_value(column, item, value)
      return periodictask_column_value(value) if column.name == :periodictask && item.is_a?(Issue)

      content = super
      if column.name == :subject && item.is_a?(Issue) && item.periodictask_issue
        content = safe_join([content, periodictask_generated_marker(item.periodictask_issue)], ' ')
      end
      content
    end

    def periodictask_column_value(task)
      return '' unless task

      if task.visible?
        link_to task.subject, periodictask_path(project_id: task.project, id: task.id), class: 'periodictask-link'
      else
        h(task.subject)
      end
    end

    def periodictask_generated_marker(link)
      title = "#{l(:label_issue_created_by_periodictask)} ##{link.periodictask_id}"
      periodictask_marker_icon('reload', 'icon-reload periodictask-generated', title)
    end
  end
end
