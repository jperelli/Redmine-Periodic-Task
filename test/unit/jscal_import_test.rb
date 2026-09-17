require "#{File.dirname(__FILE__)}/../test_helper"

# Mapping of JSCalendar (RFC 8984) Tasks and Events with recurrenceRules
# onto the schedule of a periodic task. The rule mapping itself is shared
# with the iCalendar import and covered there; here the JSON reading and the
# RecurrenceRule -> RRULE translation.
class JscalImportTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 3, 1, 12, 0, 0)

  def test_reads_the_tasks_and_events_of_a_group_and_counts_the_rest
    group = {
      '@type' => 'Group', 'uid' => 'group-1', 'title' => 'Chores',
      'entries' => [
        { '@type' => 'Task', 'uid' => 'todo-1', 'title' => 'Water the plants',
          'description' => "Every\nday", 'start' => '2026-03-05T09:00:00', 'timeZone' => 'Etc/UTC',
          'recurrenceRules' => [{ '@type' => 'RecurrenceRule', 'frequency' => 'daily', 'interval' => 2 }] },
        { '@type' => 'Event', 'uid' => 'event-1', 'title' => 'Weekly sync',
          'start' => '2026-03-02T10:00:00', 'timeZone' => 'Europe/Paris', 'duration' => 'PT1H',
          'recurrenceRules' => [{ '@type' => 'RecurrenceRule', 'frequency' => 'weekly',
                                  'byDay' => [{ '@type' => 'NDay', 'day' => 'mo' },
                                              { '@type' => 'NDay', 'day' => 'we' }] }] },
        { '@type' => 'Task', 'uid' => 'todo-once', 'title' => 'One-off task', 'due' => '2026-04-01T00:00:00' }
      ]
    }
    result = parse(group)

    assert_equal 1, result.not_recurring
    assert_equal %w[todo-1 event-1], result.items.map(&:uid)

    todo = result.items.first
    assert_equal 'Water the plants', todo.subject
    assert_equal "Every\nday", todo.description
    assert_equal '{"frequency":"daily","interval":2}', todo.rule
    assert_equal 2, todo.attributes['interval_number']
    assert_equal 'day', todo.attributes['interval_units']
    assert_equal Time.utc(2026, 3, 5, 9, 0, 0), Time.iso8601(todo.attributes['next_run_date'])
    assert_empty todo.warnings

    event = result.items.last
    assert_equal 'week', event.attributes['interval_units']
    assert_equal [1, 3], event.attributes['weekdays']
    assert_equal Time.utc(2026, 3, 2, 9, 0, 0), Time.iso8601(event.attributes['next_run_date'])
  end

  def test_reads_a_single_object_and_an_array_of_objects
    daily = [{ 'frequency' => 'daily' }]
    single = parse({ '@type' => 'Task', 'uid' => 'a', 'title' => 'A', 'recurrenceRules' => daily })
    assert_equal %w[a], single.items.map(&:uid)

    array = parse([{ '@type' => 'Task', 'uid' => 'b', 'title' => 'B', 'recurrenceRules' => daily },
                   { '@type' => 'Group', 'entries' => [{ 'uid' => 'c', 'title' => 'C', 'recurrenceRules' => daily }] },
                   { '@type' => 'Participant', 'name' => 'Not an entry' }])
    assert_equal %w[b c], array.items.map(&:uid)
  end

  def test_floating_times_due_dates_and_utc_are_read_in_the_right_zone
    zone = ActiveSupport::TimeZone['America/Argentina/Buenos_Aires']
    result = parse([task('start' => '2026-03-10T08:00:00'),
                    task('due' => '2026-04-01T00:00:00'),
                    task('start' => '2026-03-10T08:00:00Z'),
                    task('start' => '2026-03-10T08:00:00.500', 'timeZone' => 'Europe/Madrid')], zone: zone)

    runs = result.items.map { |item| Time.iso8601(item.attributes['next_run_date']) }
    assert_equal zone.local(2026, 3, 10, 8, 0, 0), runs[0]
    assert_equal zone.local(2026, 4, 1, 0, 0, 0), runs[1]
    assert_equal Time.utc(2026, 3, 10, 8, 0, 0), runs[2]
    assert_equal Time.utc(2026, 3, 10, 7, 0, 0), runs[3]
  end

  def test_unknown_time_zone_falls_back_with_one_warning
    result = parse(task('start' => '2026-03-10T08:00:00', 'timeZone' => 'Mars/Olympus',
                        'recurrenceRules' => [{ 'frequency' => 'daily', 'until' => '2026-12-31T23:59:59' }]))

    item = result.items.first
    assert_equal Time.utc(2026, 3, 10, 8, 0, 0), Time.iso8601(item.attributes['next_run_date'])
    assert_equal Time.utc(2026, 12, 31, 23, 59, 59), Time.iso8601(item.attributes['end_date'])
    assert_equal [{ 'key' => 'timezone_unknown', 'part' => 'Mars/Olympus' }], item.warnings
  end

  def test_recurrence_rule_properties_become_rrule_parts
    result = parse(task('start' => '2026-03-02T09:00:00', 'recurrenceRules' => [{
                          '@type' => 'RecurrenceRule', 'frequency' => 'monthly', 'interval' => 2,
                          'byDay' => [{ 'day' => 'mo', 'nthOfPeriod' => 1 }, { 'day' => 'fr', 'nthOfPeriod' => -1 }],
                          'count' => 6, 'firstDayOfWeek' => 'su', 'rscale' => 'gregorian', 'skip' => 'omit'
                        }]))

    attributes = result.items.first.attributes
    assert_equal 'month', attributes['interval_units']
    assert_equal 2, attributes['interval_number']
    assert_equal 'weekday', attributes['monthly_mode']
    assert_equal [1, 5], attributes['month_weeks']
    assert_equal [1, 5], attributes['weekdays']
    assert_equal 6, attributes['max_occurrences']
    assert_equal [{ 'key' => 'count_from_import', 'part' => 'COUNT=6' }], result.items.first.warnings
  end

  def test_until_is_read_in_the_entry_zone
    result = parse(task('start' => '2026-03-02T09:00:00', 'timeZone' => 'Europe/Paris',
                        'recurrenceRules' => [{ 'frequency' => 'weekly', 'until' => '2026-12-31T23:59:59' }]))

    assert_equal Time.utc(2026, 12, 31, 22, 59, 59), Time.iso8601(result.items.first.attributes['end_date'])
  end

  def test_monthly_by_month_day_and_set_position
    result = parse([task('start' => '2026-03-02T09:00:00',
                         'recurrenceRules' => [{ 'frequency' => 'monthly', 'byMonthDay' => [15, -1] }]),
                    task('start' => '2026-03-02T09:00:00',
                         'recurrenceRules' => [{ 'frequency' => 'monthly', 'byDay' => [{ 'day' => 'tu' }],
                                                 'bySetPosition' => [2] }])])

    by_month_day, by_set_position = result.items
    assert_equal Time.utc(2026, 3, 15, 9, 0, 0), Time.iso8601(by_month_day.attributes['next_run_date'])
    assert_equal [{ 'key' => 'part_ignored', 'part' => 'BYMONTHDAY=-1' },
                  { 'key' => 'monthday_moved', 'part' => 'BYMONTHDAY=15' }], by_month_day.warnings
    assert_equal [2], by_set_position.attributes['month_weeks']
    assert_equal [2], by_set_position.attributes['weekdays']
    assert_empty by_set_position.warnings
  end

  def test_items_that_already_ended_or_repeat_too_often_are_skipped
    result = parse([task('title' => 'Old', 'start' => '2025-01-01T09:00:00',
                         'recurrenceRules' => [{ 'frequency' => 'weekly', 'until' => '2025-06-01T00:00:00' }]),
                    task('title' => 'Hourly', 'start' => '2026-03-02T09:00:00',
                         'recurrenceRules' => [{ 'frequency' => 'hourly' }])])

    assert_empty result.items
    assert_equal ['Old'], result.ended
    assert_equal ['Hourly'], result.unsupported
  end

  def test_unmapped_rule_properties_further_rules_and_exceptions_are_reported
    result = parse(task(
                     'start' => '2026-03-02T09:00:00',
                     'recurrenceRules' => [{ 'frequency' => 'yearly', 'byMonth' => %w[1 4 7 10],
                                             'byDay' => [{ 'day' => 'mo' }], 'rscale' => 'hebrew',
                                             'skip' => 'forward' },
                                           { 'frequency' => 'daily' }],
                     'excludedRecurrenceRules' => [{ 'frequency' => 'weekly' }],
                     'recurrenceOverrides' => { '2026-04-06T09:00:00' => { 'excluded' => true } }
                   ))

    item = result.items.first
    assert_equal 'year', item.attributes['interval_units']
    assert_equal [], item.attributes['weekdays']
    assert_equal [{ 'key' => 'part_ignored', 'part' => 'BYDAY=MO' },
                  { 'key' => 'part_ignored', 'part' => 'BYMONTH=1,4,7,10' },
                  { 'key' => 'part_ignored', 'part' => 'RSCALE=hebrew' },
                  { 'key' => 'part_ignored', 'part' => 'SKIP=forward' },
                  { 'key' => 'part_ignored', 'part' => 'recurrenceRules[1..1]' },
                  { 'key' => 'part_ignored', 'part' => 'excludedRecurrenceRules' },
                  { 'key' => 'part_ignored', 'part' => 'recurrenceOverrides' }], item.warnings
  end

  def test_missing_title_and_start
    result = parse(task('title' => nil, 'recurrenceRules' => [{ 'frequency' => 'daily' }]))

    item = result.items.first
    assert_equal I18n.t(:label_periodictask_import_no_subject), item.subject
    assert_nil item.description
    assert_nil item.attributes['next_run_date']
  end

  def test_input_that_is_not_jscalendar_is_rejected
    ['not json', 'BEGIN:VCALENDAR', '"a string"', '42', ''].each do |text|
      assert_raises(RedminePeriodictask::CalendarImport::InvalidFile, text) do
        RedminePeriodictask::JscalImport.parse(text, now: NOW)
      end
    end
    assert_empty RedminePeriodictask::JscalImport.parse('{}', now: NOW).items
  end

  def test_imported_attributes_make_a_valid_periodictask
    result = parse(task('start' => '2026-03-02T09:00:00', 'timeZone' => 'Etc/UTC',
                        'recurrenceRules' => [{ 'frequency' => 'monthly', 'count' => 6,
                                                'byDay' => [{ 'day' => 'mo', 'nthOfPeriod' => 1 },
                                                            { 'day' => 'mo', 'nthOfPeriod' => 3 }] }]))

    task = Periodictask.new(result.items.first.attributes.slice(*Periodictask::IMPORT_ATTRIBUTES))
    task.subject = 'x'
    task.valid?
    base_errors = task.errors.select { |e| e.attribute == :base }.map(&:message)
    assert_empty base_errors
    assert task.monthly_weekday_mode?
    assert_equal Time.utc(2026, 3, 2, 9, 0, 0), task.next_run_date
  end

  private

  def parse(data, zone: ActiveSupport::TimeZone['UTC'])
    RedminePeriodictask::JscalImport.parse(JSON.generate(data), zone: zone, now: NOW)
  end

  def task(properties)
    { '@type' => 'Task', 'uid' => SecureRandom.hex(4), 'title' => 'Item',
      'recurrenceRules' => [{ 'frequency' => 'daily' }] }.merge(properties)
  end
end
