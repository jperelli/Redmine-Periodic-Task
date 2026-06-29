module PeriodictaskHelper
  # Localized label for an interval/due-date unit value (e.g. 'business_day').
  def periodictask_unit_label(value)
    Periodictask.interval_units_options.find { |(_, v)| v == value }&.first || value
  end

  # Formatted time for display, with the full ISO 8601 timestamp (including the
  # timezone offset) shown as a tooltip on hover.
  def periodictask_time_with_title(time)
    return '-' if time.blank?

    content_tag(:span, format_time(time), title: time.iso8601)
  end

  # Link to the parent issue, falling back to a plain "#id" when the issue is
  # missing or not visible, and "-" when no parent is set.
  def periodictask_parent_link(task)
    return '-' if task.parent_id.blank?

    issue = Issue.visible.find_by(id: task.parent_id)
    issue ? link_to_issue(issue) : "##{task.parent_id}"
  end

  # Initial set of users shown as checkboxes in the watchers picker:
  # the already-selected watchers plus the project's assignable watchers
  # (only when the list is short enough), mirroring Redmine's issue form.
  def users_for_new_periodictask_watchers(periodictask)
    users = User.where(id: periodictask.watcher_user_ids, status: User::STATUS_ACTIVE).to_a
    assignable_watchers = periodictask.project.principals.assignable_watchers.limit(21)
    users += assignable_watchers.sort if assignable_watchers.size <= 20
    users.uniq
  end

  def checklistPluginInstalled?
    Redmine::Plugin.all.any? { |p| p.id == :redmine_checklists } && Object.const_defined?('ChecklistTemplate')
  end

  def template_options_for_select(project = nil, selected_id = nil)
    scoped = ChecklistTemplate.visible
    scoped = scoped.in_project_and_global(project) if project.present?
    templates = scoped.eager_load(:category).to_a
    without_category = templates.select do |x|
      x.category.nil?
    end.map { |x| [x.name, x.id, { 'data-template-items' => x.template_items }] }
    with_category = templates.select { |x| x.category }
    options_for_select(
      [[l(:label_select_template), '']] + without_category,
      selected: selected_id
    ) +
      grouped_options_for_select(
        with_category.group_by { |x| x.category.try(:name) }
        .map { |k, v| [k, v.map { |x| [x.name, x.id, { 'data-template-items' => x.template_items }] }] },
        selected: selected_id
      )
  end
end
