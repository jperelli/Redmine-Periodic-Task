module RedminePeriodictask
  # Adds the "Periodic task" filter and column to the issue list, saved
  # queries and the REST issues API (issues.json?periodictask=<id>).
  module IssueQueryPatch
    def initialize_available_filters
      super
      add_available_filter 'periodictask', type: :list_optional, values: -> { periodictask_filter_values }
    end

    def available_columns
      columns = super
      columns << PeriodictaskQueryColumn.new unless columns.any? { |c| c.name == :periodictask }
      columns
    end

    # "any"/"none" are the generic `*`/`!*` operators of a list_optional filter.
    def sql_for_periodictask_field(_field, operator, value)
      links = PeriodictaskIssue.table_name
      subquery = "SELECT #{links}.issue_id FROM #{links}"
      if %w[= !].include?(operator)
        ids = value.filter_map { |v| Integer(v.to_s, 10, exception: false) }
        return operator == '=' ? '1=0' : '1=1' if ids.empty?

        subquery += " WHERE #{links}.periodictask_id IN (#{ids.join(',')})"
      end
      negate = %w[! !*].include?(operator) ? 'NOT ' : ''
      "#{Issue.table_name}.id #{negate}IN (#{subquery})"
    end

    # Loads the generating task of the page's issues in one query (two with the
    # column or grouping): the recurrence marker needs the join row on every
    # list, the column and grouping need the task itself.
    def issues(options = {})
      issues = super
      links = PeriodictaskIssue.where(issue_id: issues.map(&:id)).index_by(&:issue_id)
      with_tasks = has_column?(:periodictask) || group_by_column.is_a?(PeriodictaskQueryColumn)
      tasks = with_tasks ? Periodictask.where(id: links.values.map(&:periodictask_id)).index_by(&:id) : {}
      issues.each do |issue|
        link = links[issue.id]
        issue.association(:periodictask_issue).target = link
        issue.association(:periodictask).target = link && tasks[link.periodictask_id] if with_tasks
      end
      issues
    end

    # Tasks the user may manage: the query project and its subprojects, or
    # every project when the query is global.
    def periodictask_filter_values
      tasks = Periodictask.visible.includes(:project)
      tasks = tasks.where(project_id: project.self_and_descendants.select(:id)) if project
      tasks.sort_by { |t| [t.project.lft, t.subject, t.id] }.map { |t| [t.subject, t.id.to_s, t.project.name] }
    end

    private

    # The GROUP BY statement yields task ids; hand back the tasks so the group
    # counts line up with the column's group_value.
    def grouped_query(&)
      result = super
      if result.is_a?(Hash) && group_by_column.is_a?(PeriodictaskQueryColumn)
        tasks = Periodictask.where(id: result.keys.compact).index_by(&:id)
        result = result.transform_keys { |id| id && tasks[id.to_i] }
      end
      result
    end
  end
end
