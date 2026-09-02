module PeriodictaskHelper
  # Renders an icon + label using Redmine 6's sprite_icon when available, and
  # falls back to the plain label on Redmine 5, where the icon is supplied by
  # the link's `icon icon-*` CSS class instead.
  def periodictask_sprite_icon(name, label = nil, **)
    return sprite_icon(name, label, **) if respond_to?(:sprite_icon)

    label
  end

  # Localized label for an interval/due-date unit value (e.g. 'business_day').
  def periodictask_unit_label(value)
    Periodictask.interval_units_options.find { |(_, v)| v == value }&.first || value
  end

  def periodictask_default_label(value)
    ["(#{l(:label_default)})", value].compact.join(' - ')
  end

  # Parses a wall-clock datetime (no offset) in the zone Redmine's format_time
  # uses for the current user: their preference when set, otherwise the
  # server's local zone.
  def periodictask_parse_time(value)
    zone = User.current.time_zone
    zone ? zone.parse(value) : Time.parse(value)
  end

  # Value for the next_run_date datetime-local input, in the display zone.
  def periodictask_next_run_date_input_value(time)
    return if time.blank?

    zone = User.current.time_zone
    (zone ? time.in_time_zone(zone) : time.getlocal).strftime('%Y-%m-%dT%H:%M')
  end

  # Zone name and UTC offset shown next to the next_run_date input.
  def periodictask_time_zone_label
    return User.current.time_zone.to_s if User.current.time_zone

    now = Time.now
    "(GMT#{now.formatted_offset}) #{now.zone}"
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

  def checklist_plugin_installed?
    Redmine::Plugin.all.any? { |p| p.id == :redmine_checklists } && Object.const_defined?('ChecklistTemplate')
  end

  def template_options_for_select(project = nil, selected_id = nil)
    scoped = ChecklistTemplate.visible
    scoped = scoped.in_project_and_global(project) if project.present?
    templates = scoped.eager_load(:category).to_a
    uncategorized = templates.select { |x| x.category.nil? }
    without_category = uncategorized.map { |x| [x.name, x.id, { 'data-template-items' => x.template_items }] }
    with_category = templates.select(&:category)
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
