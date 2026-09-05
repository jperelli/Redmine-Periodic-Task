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

  # Human-readable schedule, e.g. "every 2 weeks on Monday, Wednesday" or
  # "each month on the 1st, 3rd Wednesday"; the single source for the list
  # and detail pages.
  def periodictask_schedule_description(task)
    interval = periodictask_interval_label(task.interval_number, task.interval_units)
    weekdays = Periodictask.ordered_weekdays.select { |d| task.weekdays.include?(d) }.map { |d| day_name(d) }.join(', ')
    case task.interval_units
    when 'week'
      return interval if weekdays.blank?

      "#{interval} #{l(:label_recurrence_on_weekdays, weekdays: weekdays)}"
    when 'month'
      if task.monthly_weekday_mode? && weekdays.present? && task.month_weeks.any?
        ordinals = task.month_weeks.map { |n| l(:"label_recurrence_ordinal_#{n}") }.join(', ')
        "#{interval} #{l(:label_recurrence_on_month_weekdays, ordinals: ordinals, weekdays: weekdays)}"
      elsif task.next_run_date
        "#{interval} #{l(:label_recurrence_on_day_of_month, day: periodictask_display_time(task.next_run_date).day)}"
      else
        interval
      end
    else
      interval
    end
  end

  # "each week" / "every 3 weeks", pluralized per locale.
  def periodictask_interval_label(number, units)
    key = :"label_recurrence_every_#{units}"
    return "#{number} #{periodictask_unit_label(units)}" unless Periodictask::INTERVAL_UNITS.include?(units)

    l(key, count: number.to_i)
  end

  # Help icon linking to the recurrence design document on GitHub.
  def periodictask_recurrence_help_link(title = l(:label_recurrence_help))
    link_to periodictask_sprite_icon('help', title, icon_only: true), RedminePeriodictask::RECURRENCE_DOC_URL,
            class: 'icon-only icon-help', title: title, target: '_blank', rel: 'noopener'
  end

  # Target version options: the project's open versions plus the task's own
  # one, so editing a task whose version has since been closed keeps it.
  def periodictask_version_options(versions, periodictask)
    version_options_for_select((versions + [periodictask.fixed_version]).compact.uniq, periodictask.fixed_version)
  end

  # Marker shown next to a disabled task's subject in the list and detail pages.
  def periodictask_disabled_icon(periodictask)
    return if periodictask.is_active?

    content_tag(:span, '', title: l(:label_disabled), class: 'icon-only icon-locked')
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

  # +time+ in the zone Redmine's format_time uses for the current user.
  def periodictask_display_time(time)
    zone = User.current.time_zone
    zone ? time.in_time_zone(zone) : time.getlocal
  end

  # Value for the next_run_date datetime-local input, in the display zone.
  def periodictask_next_run_date_input_value(time)
    return if time.blank?

    periodictask_display_time(time).strftime('%Y-%m-%dT%H:%M')
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

    periodictask_issue_link(task.parent_id)
  end

  # Localized [label, value] pairs for the relation type select, in Redmine's order.
  def periodictask_relation_type_options
    IssueRelation::TYPES.sort_by { |_, v| v[:order] }.map { |key, v| [l(v[:name]), key] }
  end

  def periodictask_relation_type_label(relation_type)
    type = IssueRelation::TYPES[relation_type.to_s]
    type ? l(type[:name]) : relation_type.to_s
  end

  # Link to a related issue, falling back to a plain "#id" when the issue is
  # missing or not visible.
  def periodictask_issue_link(issue_id)
    issue = Issue.visible.find_by(id: issue_id)
    issue ? link_to_issue(issue) : "##{issue_id}"
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
    Periodictask.checklists_plugin_installed?
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
