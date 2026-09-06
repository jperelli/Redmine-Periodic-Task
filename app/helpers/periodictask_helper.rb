module PeriodictaskHelper
  # REST API representation of a task, shared by the project list/detail and
  # the admin list. Related records follow Redmine core's `{id, name}` shape;
  # generated issues are only listed on request (`include=issues`).
  def render_api_periodictask(api, task, last_run)
    api.id task.id
    render_api_periodictask_associations(api, task)
    api.subject task.subject
    api.description task.description
    api.interval_number task.interval_number
    api.interval_units task.interval_units
    api.array(:weekdays) { task.weekdays.each { |d| api.weekday d } }
    api.monthly_mode task.monthly_mode
    api.array(:month_weeks) { task.month_weeks.each { |w| api.month_week w } }
    api.weekend_adjustment task.weekend_adjustment
    api.set_start_date task.set_start_date
    api.due_date_number task.due_date_number
    api.due_date_units task.due_date_units
    api.estimated_hours task.estimated_hours
    api.done_ratio task.done_ratio
    api.parent_id task.parent_id
    api.checklists_template_id task.checklists_template_id
    api.array(:tags) { task.tag_names.each { |t| api.tag t } }
    render_api_periodictask_custom_fields(api, task)
    api.array(:watchers) do
      User.where(id: task.watcher_user_ids).sorted.each { |u| api.user(id: u.id, name: u.name) }
    end
    api.array(:subtasks) do
      task.subtasks.each { |row| api.subtask(row.slice(*Periodictask::SUBTASK_KEYS)) }
    end
    api.array(:relations) do
      task.relations.each { |row| api.relation(row.slice(*Periodictask::RELATION_KEYS)) }
    end
    api.is_active task.is_active
    api.next_run_date task.next_run_date
    api.last_assigned_date task.last_assigned_date
    api.last_run last_run
    api.last_error task.last_error
    api.created_at task.created_at
    api.updated_at task.updated_at
    render_api_periodictask_issues(api, task) if include_in_api_response?('issues')
  end

  def render_api_periodictask_associations(api, task)
    api.project(id: task.project_id, name: task.project.name) if task.project
    api.tracker(id: task.tracker_id, name: task.tracker.name) if task.tracker
    api.author(id: task.author_id, name: task.author.name) if task.author
    api.assigned_to(id: task.assigned_to_id, name: task.assigned_to.name) if task.assigned_to
    api.category(id: task.issue_category_id, name: task.issue_category.name) if task.issue_category
    api.fixed_version(id: task.fixed_version_id, name: task.fixed_version.name) if task.fixed_version
    if task.priority_id && (priority = api_issue_priorities[task.priority_id])
      api.priority(id: priority.id, name: priority.name)
    end
    return unless task.status_id && (status = api_issue_statuses[task.status_id])

    api.status(id: status.id, name: status.name)
  end

  def render_api_periodictask_custom_fields(api, task)
    values = task.custom_field_values.respond_to?(:to_h) ? task.custom_field_values.to_h : {}
    api.array(:custom_fields) do
      values.each do |id, value|
        field = api_issue_custom_fields[id.to_i]
        next unless field

        attrs = { id: field.id, name: field.name }
        attrs[:multiple] = true if field.multiple?
        api.custom_field(attrs) do
          if value.is_a?(Array)
            api.array(:value) { value.each { |v| api.value v if v.present? } }
          else
            api.value value
          end
        end
      end
    end
  end

  def render_api_periodictask_issues(api, task)
    api.array(:issues) do
      task.periodictask_issues.joins(:issue).order(created_at: :desc).each do |link|
        api.issue do
          api.id link.issue_id
          api.created_at link.created_at
        end
      end
    end
  end

  def api_issue_priorities
    @api_issue_priorities ||= IssuePriority.all.index_by(&:id)
  end

  def api_issue_statuses
    @api_issue_statuses ||= IssueStatus.all.index_by(&:id)
  end

  def api_issue_custom_fields
    @api_issue_custom_fields ||= IssueCustomField.all.index_by(&:id)
  end

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
    periodictask_with_weekend_adjustment(periodictask_recurrence_description(task), task)
  end

  def periodictask_with_weekend_adjustment(description, task)
    return description unless task.weekend_adjusted?

    "#{description}, #{l(:"label_recurrence_weekend_adjustment_#{task.weekend_adjustment}")}"
  end

  def periodictask_recurrence_description(task)
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

  # The schedule description plus the time of day of the runs, e.g. "each month
  # on the 5th (or last) Friday at 09:00 AM"; the live sentence of the form.
  def periodictask_schedule_sentence(task, first_date)
    sentence = l(:label_recurrence_at_time, schedule: periodictask_recurrence_description(task),
                                            time: format_time(first_date, false))
    periodictask_with_weekend_adjustment(sentence, task)
  end

  # Chip for one upcoming occurrence: abbreviated weekday and date of the day the
  # task will actually run, the ISO 8601 timestamp (and the occurrence it was
  # moved from, when the working-day adjustment applied) as tooltip.
  def periodictask_run_chip(task, date, now = Time.current)
    effective = task.adjust_to_working_day(date)
    classes = ['periodictask-run-chip']
    title = periodictask_display_time(effective).iso8601
    if effective != date
      classes << 'periodictask-run-chip-moved'
      title = "#{title} (#{l(:label_weekend_adjustment_moved_from, date: format_time(date))})"
    end
    classes << 'periodictask-run-chip-overdue' if effective <= now
    content_tag(:span, periodictask_short_date(effective), class: classes.join(' '), title: title)
  end

  # "Fri 10/30/2026" in the user's zone and date format.
  def periodictask_short_date(time)
    display = periodictask_display_time(time)
    "#{::I18n.t('date.abbr_day_names')[display.wday]} #{format_date(display)}"
  end

  # Month grids highlighting the upcoming runs: one table per month touched by
  # the occurrences or by the working days they were moved to.
  def periodictask_run_calendar(task, dates, today = User.current.today)
    runs = dates.map { |d| periodictask_display_time(task.adjust_to_working_day(d)).to_date }
    moved = dates.map { |d| periodictask_display_time(d).to_date } - runs
    months = (runs + moved).map(&:beginning_of_month).uniq.sort
    working_days = Periodictask.working_days
    safe_join(months.map { |month| periodictask_month_grid(month, runs, moved, today, working_days) })
  end

  def periodictask_month_grid(month, runs, moved, today, working_days)
    weekdays = Periodictask.ordered_weekdays
    first = month
    first -= 1 until first.wday == weekdays.first
    last = month.end_of_month
    last += 1 until last.wday == weekdays.last
    head = content_tag(:tr, safe_join(weekdays.map { |d| content_tag(:th, day_letter(d), title: day_name(d)) }))
    rows = (first..last).each_slice(7).map do |week|
      cells = week.map { |day| periodictask_calendar_cell(day, month, runs, moved, today, working_days) }
      content_tag(:tr, safe_join(cells))
    end
    content_tag(:table, class: 'periodictask-cal') do
      content_tag(:caption, "#{month_name(month.month)} #{month.year}") +
        content_tag(:thead, head) + content_tag(:tbody, safe_join(rows))
    end
  end

  def periodictask_calendar_cell(day, month, runs, moved, today, working_days)
    return content_tag(:td, '', class: 'periodictask-cal-other') if day.month != month.month

    classes = []
    classes << 'nwday' unless working_days.working_day?(day)
    classes << 'today' if day == today
    classes << 'periodictask-cal-run' if runs.include?(day)
    classes << 'periodictask-cal-moved' if moved.include?(day)
    content_tag(:td, day.day.to_s, class: classes.presence&.join(' '))
  end

  # Localized label of the task's weekend_adjustment option.
  def periodictask_weekend_adjustment_label(task)
    l(:"label_weekend_adjustment_#{task.weekend_adjustment}")
  end

  # When the task will actually run: the stored occurrence, or the working day
  # it was moved to followed by the occurrence it was moved from.
  def periodictask_next_run_with_title(task)
    effective = task.effective_next_run_date
    html = periodictask_time_with_title(effective)
    return html if effective.blank? || effective == task.next_run_date

    moved_from = l(:label_weekend_adjustment_moved_from, date: format_time(task.next_run_date))
    safe_join([html, content_tag(:span, "(#{moved_from})", class: 'periodictask-moved-from')], ' ')
  end

  # "each week" / "every 3 weeks", pluralized per locale.
  def periodictask_interval_label(number, units)
    key = :"label_recurrence_every_#{units}"
    return "#{number} #{periodictask_unit_label(units)}" unless Periodictask::INTERVAL_UNITS.include?(units)

    l(key, count: number.to_i)
  end

  # Short name of an if_previous_open mode, e.g. "Skip this occurrence".
  def periodictask_if_previous_open_label(mode)
    l(:"label_if_previous_open_#{mode}")
  end

  # One-sentence explanation of an if_previous_open mode.
  def periodictask_if_previous_open_description(mode)
    l(:"label_if_previous_open_#{mode}_info")
  end

  # Options for the if_previous_open select.
  def periodictask_if_previous_open_options(selected)
    options = Periodictask::IF_PREVIOUS_OPEN_MODES.map { |mode| [periodictask_if_previous_open_label(mode), mode] }
    options_for_select(options, selected)
  end

  # Help icon linking to the if_previous_open document on GitHub.
  def periodictask_if_previous_open_help_link
    periodictask_recurrence_help_link(l(:label_if_previous_open_help), RedminePeriodictask::IF_PREVIOUS_OPEN_DOC_URL)
  end

  # "The run of <time> skipped ...: #123 was still open", shown above the
  # generated issues; the row for the run that created nothing.
  def periodictask_last_skipped_note(task)
    text = l(:text_periodictask_last_skipped, time: h(format_time(task.last_skipped_at)),
                                              issue: periodictask_issue_link(task.last_skipped_issue_id))
    safe_join([content_tag(:span, periodictask_sprite_icon('time'), class: 'icon-only icon-time'), ' ', text.html_safe])
  end

  # Help icon linking to a document on GitHub, the recurrence design by default.
  def periodictask_recurrence_help_link(title = l(:label_recurrence_help),
                                        url = RedminePeriodictask::RECURRENCE_DOC_URL)
    link_to periodictask_sprite_icon('help', title, icon_only: true), url,
            class: 'icon-only icon-help', title: title, target: '_blank', rel: 'noopener'
  end

  # Target version options: the project's open versions plus the task's own
  # one, so editing a task whose version has since been closed keeps it.
  def periodictask_version_options(versions, periodictask)
    version_options_for_select((versions + [periodictask.fixed_version]).compact.uniq, periodictask.fixed_version)
  end

  # Marker shown next to a disabled task's subject in the project and admin lists.
  def periodictask_disabled_icon(periodictask)
    return if periodictask.is_active?

    periodictask_marker_icon('lock', 'icon-locked', l(:label_disabled))
  end

  # Marker shown next to a task's subject in the lists when its last run failed;
  # the error message is the tooltip.
  def periodictask_error_icon(periodictask)
    return if periodictask.last_error.blank?

    periodictask_marker_icon('warning', 'icon-error', periodictask.last_error)
  end

  # Icon-only marker with a tooltip. Redmine 6+ needs the SVG sprite inside the
  # span (an empty `icon-*` span renders nothing since 7.0); Redmine 5 draws the
  # icon from the CSS class. Extra options (e.g. `size:`) go to sprite_icon.
  def periodictask_marker_icon(sprite, css_class, title, **)
    content_tag(:span, periodictask_sprite_icon(sprite, **), title: title, class: "icon-only #{css_class}")
  end

  def periodictask_default_label(value)
    ["(#{l(:label_default)})", value].compact.join(' - ')
  end

  # "(Default)" plus a help icon explaining Redmine's default assignee rules,
  # shown when a task has no assignee configured.
  def periodictask_default_assignee_label
    help = periodictask_marker_icon('help', 'icon-help', l(:label_assigned_to_info))
    safe_join([periodictask_default_label(nil), help], ' ')
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

  # [label, value] pairs for the relation target select: a fixed issue number
  # or the issue generated by the previous run.
  def periodictask_relation_target_options
    [[l(:label_issue), 'issue'], [l(:label_relation_previous_issue), Periodictask::RELATION_PREVIOUS_ISSUE]]
  end

  # Target of a relation template on the detail page: the previous-issue
  # label or a link to the fixed issue.
  def periodictask_relation_target(row)
    return l(:label_relation_previous_issue) if Periodictask.previous_issue_relation?(row)

    periodictask_issue_link(row['issue_id'])
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
