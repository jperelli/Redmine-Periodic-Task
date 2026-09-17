require "#{File.dirname(__FILE__)}/../test_helper"

# Mapping of iCalendar recurring items (VTODO / VEVENT with an RRULE) onto
# the schedule of a periodic task.
class IcalImportTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 3, 1, 12, 0, 0)

  def test_reads_recurring_todos_and_events_and_counts_the_rest
    result = parse(<<~ICS)
      BEGIN:VCALENDAR
      BEGIN:VTODO
      UID:todo-1
      SUMMARY:Water the plants
      DESCRIPTION:Every\\, single\\nday\\; really
      DTSTART:20260305T090000Z
      RRULE:FREQ=DAILY;INTERVAL=2
      BEGIN:VALARM
      SUMMARY:Alarm summary is not the item's
      END:VALARM
      END:VTODO
      BEGIN:VEVENT
      UID:event-1
      SUMMARY:Weekly sync
      DTSTART;TZID=Europe/Paris:20260302T100000
      RRULE:FREQ=WEEKLY;BYDAY=MO,WE
      END:VEVENT
      BEGIN:VTODO
      UID:todo-once
      SUMMARY:One-off task
      END:VTODO
      END:VCALENDAR
    ICS

    assert_equal 1, result.not_recurring
    assert_equal %w[todo-1 event-1], result.items.map(&:uid)

    todo = result.items.first
    assert_equal 'Water the plants', todo.subject
    assert_equal "Every, single\nday; really", todo.description
    assert_equal 'FREQ=DAILY;INTERVAL=2', todo.rule
    assert_equal 2, todo.attributes['interval_number']
    assert_equal 'day', todo.attributes['interval_units']
    assert_equal Time.utc(2026, 3, 5, 9, 0, 0), Time.iso8601(todo.attributes['next_run_date'])
    assert_empty todo.warnings

    event = result.items.last
    assert_equal 'week', event.attributes['interval_units']
    assert_equal [1, 3], event.attributes['weekdays']
    assert_equal Time.utc(2026, 3, 2, 9, 0, 0), Time.iso8601(event.attributes['next_run_date'])
  end

  def test_floating_times_and_dates_are_read_in_the_given_zone
    zone = ActiveSupport::TimeZone['America/Argentina/Buenos_Aires']
    text = item('DTSTART:20260310T080000', 'RRULE:FREQ=DAILY') + item('DUE;VALUE=DATE:20260401', 'RRULE:FREQ=WEEKLY')
    result = parse(text, zone: zone)

    assert_equal zone.local(2026, 3, 10, 8, 0, 0), Time.iso8601(result.items[0].attributes['next_run_date'])
    assert_equal zone.local(2026, 4, 1, 0, 0, 0), Time.iso8601(result.items[1].attributes['next_run_date'])
  end

  def test_unknown_time_zone_falls_back_with_a_warning
    result = parse(item('DTSTART;TZID=W. Europe Standard Time:20260310T080000', 'RRULE:FREQ=DAILY'))

    assert_equal Time.utc(2026, 3, 10, 8, 0, 0), Time.iso8601(result.items.first.attributes['next_run_date'])
    assert_equal [{ 'key' => 'timezone_unknown', 'part' => 'W. Europe Standard Time' }], result.items.first.warnings
  end

  def test_daily_with_weekday_list_becomes_a_weekly_task
    result = parse(item('DTSTART:20260302T090000Z', 'RRULE:FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR'))

    attributes = result.items.first.attributes
    assert_equal 'week', attributes['interval_units']
    assert_equal 1, attributes['interval_number']
    assert_equal [1, 2, 3, 4, 5], attributes['weekdays']
  end

  def test_monthly_ordinal_weekdays
    result = parse(item('DTSTART:20260302T090000Z', 'RRULE:FREQ=MONTHLY;INTERVAL=2;BYDAY=1MO,-1FR'))

    attributes = result.items.first.attributes
    assert_equal 'month', attributes['interval_units']
    assert_equal 2, attributes['interval_number']
    assert_equal 'weekday', attributes['monthly_mode']
    assert_equal [1, 5], attributes['month_weeks']
    assert_equal [1, 5], attributes['weekdays']
    assert_empty result.items.first.warnings
  end

  def test_monthly_weekday_with_bysetpos_and_without_ordinal
    result = parse(item('DTSTART:20260302T090000Z', 'RRULE:FREQ=MONTHLY;BYDAY=TU;BYSETPOS=2') +
                   item('DTSTART:20260302T090000Z', 'RRULE:FREQ=MONTHLY;BYDAY=TU'))

    assert_equal [2], result.items[0].attributes['month_weeks']
    assert_empty result.items[0].warnings
    assert_equal [1, 2, 3, 4, 5], result.items[1].attributes['month_weeks']
    assert_equal [2], result.items[1].attributes['weekdays']
  end

  def test_monthly_by_month_day_moves_the_anchor_and_reports_the_rest
    result = parse(item('DTSTART:20260302T090000Z', 'RRULE:FREQ=MONTHLY;BYMONTHDAY=15,-1'))

    attributes = result.items.first.attributes
    assert_equal 'day_of_month', Periodictask.new(attributes.slice(*Periodictask::IMPORT_ATTRIBUTES)).monthly_mode
    assert_equal Time.utc(2026, 3, 15, 9, 0, 0), Time.iso8601(attributes['next_run_date'])
    assert_equal [{ 'key' => 'part_ignored', 'part' => 'BYMONTHDAY=-1' },
                  { 'key' => 'monthday_moved', 'part' => 'BYMONTHDAY=15' }], result.items.first.warnings
  end

  def test_last_day_of_the_month_is_the_last_day_of_the_start_month
    result = parse(item('DTSTART:20260131T090000Z', 'RRULE:FREQ=MONTHLY;BYMONTHDAY=-1') +
                   item('DTSTART:20260228T090000Z', 'RRULE:FREQ=MONTHLY;BYMONTHDAY=-1') +
                   item('DTSTART:20260401T090000Z', 'RRULE:FREQ=MONTHLY;BYMONTHDAY=-1'))

    starts = result.items.map { |i| Time.iso8601(i.attributes['next_run_date']) }
    assert_equal [Time.utc(2026, 1, 31, 9), Time.utc(2026, 2, 28, 9), Time.utc(2026, 4, 30, 9)], starts
    assert_equal [[], [], [{ 'key' => 'monthday_moved', 'part' => 'BYMONTHDAY=-1' }]], result.items.map(&:warnings)
    assert_equal(['month'] * 3, result.items.map { |i| i.attributes['interval_units'] })
  end

  def test_cancelled_items_become_inactive_tasks
    result = parse(item('DTSTART:20260302T090000Z', 'RRULE:FREQ=DAILY', 'STATUS:CANCELLED') +
                   item('DTSTART:20260302T090000Z', 'RRULE:FREQ=DAILY', 'STATUS:NEEDS-ACTION') +
                   item('DTSTART:20260302T090000Z', 'RRULE:FREQ=DAILY'))

    assert_equal([false, nil, nil], result.items.map { |i| i.attributes['is_active'] })
    task = Periodictask.new(result.items.first.attributes.slice(*Periodictask::IMPORT_ATTRIBUTES))
    assert_equal false, task.is_active
  end

  def test_count_and_until_become_the_end_condition
    result = parse(item('DTSTART:20260302T090000Z', 'RRULE:FREQ=WEEKLY;COUNT=10') +
                   item('DTSTART:20260302T090000Z', 'RRULE:FREQ=WEEKLY;UNTIL=20261231T235959Z') +
                   item('DTSTART:20260302', 'RRULE:FREQ=YEARLY;UNTIL=20261231'))

    counted, until_time, until_date = result.items
    assert_equal 10, counted.attributes['max_occurrences']
    assert_nil counted.attributes['end_date']
    assert_equal [{ 'key' => 'count_from_import', 'part' => 'COUNT=10' }], counted.warnings
    assert_nil until_time.attributes['max_occurrences']
    assert_equal Time.utc(2026, 12, 31, 23, 59, 59), Time.iso8601(until_time.attributes['end_date'])
    assert_equal Time.utc(2026, 12, 31, 0, 0, 0), Time.iso8601(until_date.attributes['end_date'])
  end

  def test_items_that_already_ended_or_repeat_too_often_are_skipped
    result = parse(item('DTSTART:20250101T090000Z', 'RRULE:FREQ=WEEKLY;UNTIL=20250601T000000Z', summary: 'Old') +
                   item('DTSTART:20260302T090000Z', 'RRULE:FREQ=HOURLY', summary: 'Hourly') +
                   item('DTSTART:20260302T090000Z', 'RRULE:FREQ=MINUTELY;INTERVAL=30', summary: 'Half hourly'))

    assert_empty result.items
    assert_equal ['Old'], result.ended
    assert_equal ['Hourly', 'Half hourly'], result.unsupported
  end

  def test_unmapped_rule_parts_and_exceptions_are_reported
    result = parse(<<~ICS)
      BEGIN:VEVENT
      UID:x
      SUMMARY:Quarterly
      DTSTART:20260302T090000Z
      RRULE:FREQ=YEARLY;BYMONTH=1,4,7,10;BYDAY=MO;WKST=SU
      EXDATE:20260406T090000Z
      END:VEVENT
    ICS

    item = result.items.first
    assert_equal 'year', item.attributes['interval_units']
    assert_equal [], item.attributes['weekdays']
    assert_equal [{ 'key' => 'part_ignored', 'part' => 'BYDAY=MO' },
                  { 'key' => 'part_ignored', 'part' => 'BYMONTH=1,4,7,10' },
                  { 'key' => 'part_ignored', 'part' => 'EXDATE' }], item.warnings
  end

  def test_folded_lines_crlf_and_missing_summary
    text = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:folded\r\nDESCRIPTION:A very long\r\n  line that continues\r\n" \
           "RRULE:FREQ=DAILY\r\nEND:VTODO\r\nEND:VCALENDAR\r\n"
    result = parse(text)

    item = result.items.first
    assert_equal 'A very long line that continues', item.description
    assert_equal I18n.t(:label_periodictask_import_no_subject), item.subject
    assert_nil item.attributes['next_run_date']
  end

  def test_garbage_input_is_not_a_calendar
    assert_raises(RedminePeriodictask::CalendarImport::InvalidFile) { parse("not a calendar\nat all") }
    assert_raises(RedminePeriodictask::CalendarImport::InvalidFile) { parse('{"@type": "Task"}') }
  end

  def test_a_calendar_without_recurring_items_yields_nothing
    result = parse("BEGIN:VCALENDAR\nEND:VCALENDAR\n")

    assert_empty result.items
    assert_equal 0, result.not_recurring
  end

  def test_imported_attributes_make_a_valid_periodictask
    result = parse(item('DTSTART:20260302T090000Z', 'RRULE:FREQ=MONTHLY;BYDAY=1MO,3MO;COUNT=6'))

    task = Periodictask.new(result.items.first.attributes.slice(*Periodictask::IMPORT_ATTRIBUTES))
    task.subject = 'x'
    task.valid?
    base_errors = task.errors.select { |e| e.attribute == :base }.map(&:message)
    assert_empty base_errors
    assert task.monthly_weekday_mode?
    assert_equal Time.utc(2026, 3, 2, 9, 0, 0), task.next_run_date
  end

  private

  def parse(text, zone: ActiveSupport::TimeZone['UTC'])
    RedminePeriodictask::IcalImport.parse(text, zone: zone, now: NOW)
  end

  def item(*lines, summary: 'Item')
    "BEGIN:VEVENT\nUID:#{SecureRandom.hex(4)}\nSUMMARY:#{summary}\n#{lines.join("\n")}\nEND:VEVENT\n"
  end
end
