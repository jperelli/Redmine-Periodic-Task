require "#{File.dirname(__FILE__)}/../test_helper"

# Periodic tasks written as iCalendar VTODOs with an RRULE, and read back by
# the importer as the same schedule.
class IcalExportTest < ActiveSupport::TestCase
  fixtures :projects, :users, :trackers, :enumerations

  NOW = Time.utc(2026, 3, 1, 12, 0, 0)

  def setup
    Periodictask.delete_all
    @project = Project.find(1)
    Setting.host_name = 'redmine.example.com'
    Setting.protocol = 'https'
    Setting.start_of_week = '1'
  end

  def test_writes_a_calendar_with_one_todo_per_task
    daily = task(subject: 'Water the plants', description: "Every, single\nday; really",
                 interval_units: 'day', interval_number: 2, next_run_date: Time.utc(2026, 3, 5, 9))
    weekly = task(subject: 'Weekly sync', interval_units: 'week', weekdays: [1, 3],
                  next_run_date: Time.utc(2026, 3, 2, 9), tag_list: 'ops, team')

    ics = export([daily, weekly])
    lines = ics.split("\r\n")

    assert_equal 'BEGIN:VCALENDAR', lines.first
    assert_equal 'END:VCALENDAR', lines.last
    assert_includes lines, 'VERSION:2.0'
    assert_includes lines, 'PRODID:-//Redmine Periodic Task//EN'
    assert_equal 2, lines.count('BEGIN:VTODO')
    assert_equal 2, lines.count('END:VTODO')
    assert ics.end_with?("\r\n")

    assert_includes lines, "UID:periodictask-#{daily.id}@redmine.example.com"
    assert_includes lines, "DTSTAMP:#{NOW.strftime('%Y%m%dT%H%M%SZ')}"
    assert_includes lines, 'DTSTART:20260305T090000Z'
    assert_includes lines, 'RRULE:FREQ=DAILY;INTERVAL=2'
    assert_includes lines, 'SUMMARY:Water the plants'
    assert_includes lines, 'DESCRIPTION:Every\\, single\\nday\\; really'
    assert_includes lines, 'STATUS:NEEDS-ACTION'
    assert_includes lines, "URL:https://redmine.example.com/projects/ecookbook/periodictask/#{daily.id}"

    assert_includes lines, 'RRULE:FREQ=WEEKLY;BYDAY=MO,WE;WKST=MO'
    assert_includes lines, 'CATEGORIES:ops,team'
    assert_equal 1, lines.count { |line| line.start_with?('DESCRIPTION:') }, 'a blank description is not written'
    assert_equal 1, lines.count { |line| line.start_with?('CATEGORIES:') }, 'tags are written once'
  end

  def test_dtstart_is_in_the_given_zone
    weekly = task(interval_units: 'week', weekdays: [2], next_run_date: Time.utc(2026, 3, 3, 1)) # Tue 01:00 UTC

    lines = export([weekly], zone: ActiveSupport::TimeZone['Buenos Aires']).split("\r\n") # Mon 22:00 in -03:00
    assert_includes lines, 'DTSTART;TZID=America/Argentina/Buenos_Aires:20260302T220000'
  end

  def test_format_registry_and_filenames
    exporters = RedminePeriodictask::CalendarExport.exporters
    formats = exporters.map { |exporter| exporter::FORMAT }
    assert_equal %w[ics jscal cron], formats
    assert_equal RedminePeriodictask::IcalExport, RedminePeriodictask::CalendarExport.for_format('ics')
    assert_nil RedminePeriodictask::CalendarExport.for_format('pdf')
    assert_equal 'periodictasks-ecookbook.ics', RedminePeriodictask::IcalExport.filename('ecookbook')
    assert_equal 'periodictasks-all.json', RedminePeriodictask::JscalExport.filename('all')
    assert_equal 'periodictasks-all.txt', RedminePeriodictask::CronExport.filename('all')
  end

  def test_rrule_per_schedule
    assert_equal 'FREQ=DAILY', rrule(interval_units: 'day')
    assert_equal 'FREQ=DAILY;INTERVAL=3', rrule(interval_units: 'day', interval_number: 3)
    assert_equal 'FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR', rrule(interval_units: 'business_day')
    assert_equal 'FREQ=WEEKLY;INTERVAL=2', rrule(interval_units: 'week', interval_number: 2)
    assert_equal 'FREQ=WEEKLY;BYDAY=SU,SA;WKST=MO', rrule(interval_units: 'week', weekdays: [0, 6])
    assert_equal 'FREQ=MONTHLY', rrule(interval_units: 'month')
    assert_equal 'FREQ=MONTHLY;BYDAY=1MO,1WE,3MO,3WE',
                 rrule(interval_units: 'month', monthly_mode: 'weekday', weekdays: [1, 3], month_weeks: [1, 3])
    assert_equal 'FREQ=MONTHLY;INTERVAL=2;BYDAY=-1FR',
                 rrule(interval_units: 'month', interval_number: 2, monthly_mode: 'weekday', weekdays: [5],
                       month_weeks: [5])
    assert_equal 'FREQ=YEARLY', rrule(interval_units: 'year')
  end

  def test_wkst_follows_the_start_of_week_setting
    with_settings start_of_week: '7' do
      assert_equal 'FREQ=WEEKLY;BYDAY=MO;WKST=SU', rrule(interval_units: 'week', weekdays: [1])
    end
  end

  def test_end_conditions
    assert_equal 'FREQ=DAILY;UNTIL=20261231T230000Z', rrule(interval_units: 'day', end_date: Time.utc(2026, 12, 31, 23))
    assert_equal 'FREQ=DAILY;COUNT=7', rrule(interval_units: 'day', max_occurrences: 10, occurrences_count: 3)
  end

  def test_with_both_end_conditions_the_one_that_stops_the_task_first_is_written
    end_date = Time.utc(2026, 4, 10, 23) # the daily task starts April 1st: 10 runs fit
    assert_equal 'FREQ=DAILY;COUNT=7',
                 rrule(interval_units: 'day', end_date: end_date, max_occurrences: 10, occurrences_count: 3)
    assert_equal 'FREQ=DAILY;COUNT=10', rrule(interval_units: 'day', end_date: end_date, max_occurrences: 10)
    assert_equal 'FREQ=DAILY;UNTIL=20260410T230000Z',
                 rrule(interval_units: 'day', end_date: end_date, max_occurrences: 11)
  end

  def test_ended_task_is_a_completed_todo_without_rrule
    done = task(subject: 'Done', max_occurrences: 3, occurrences_count: 3)
    over = task(subject: 'Over', end_date: Time.utc(2026, 4, 30))
    over.update_columns(end_date: Time.utc(2026, 3, 31)) # as the scheduler leaves it after the last run

    lines = export([done, over]).split("\r\n")
    assert_equal 2, lines.count('STATUS:COMPLETED')
    assert_empty lines.grep(/\ARRULE:/)
    assert_includes lines, 'DTSTART:20260401T090000Z'
  end

  def test_business_days_follow_the_non_working_days_setting
    with_settings non_working_week_days: %w[5 6 7] do
      assert_equal 'FREQ=DAILY;BYDAY=MO,TU,WE,TH', rrule(interval_units: 'business_day')
    end
  end

  def test_every_n_business_days_is_written_approximately_with_a_comment
    ics = export([task(interval_units: 'business_day', interval_number: 3)])
    lines = ics.gsub("\r\n ", '').split("\r\n") # unfolded
    assert_includes lines, 'RRULE:FREQ=DAILY;INTERVAL=3;BYDAY=MO,TU,WE,TH,FR'
    note = lines.grep(/\ACOMMENT:/)
    assert_equal 1, note.size
    assert_match(/every 3 business days/, note.first)
    assert_match(/approximation/, note.first)

    assert_empty export([task(interval_units: 'business_day')]).split("\r\n").grep(/\ACOMMENT:/)
  end

  def test_monthly_task_on_the_31st_is_the_last_day_of_the_month
    assert_equal 'FREQ=MONTHLY;BYMONTHDAY=-1', rrule(interval_units: 'month', next_run_date: Time.utc(2026, 3, 31, 9))
    assert_equal 'FREQ=MONTHLY', rrule(interval_units: 'month', next_run_date: Time.utc(2026, 3, 30, 9))
    assert_equal 'FREQ=MONTHLY;BYDAY=-1FR',
                 rrule(interval_units: 'month', monthly_mode: 'weekday', weekdays: [5], month_weeks: [5],
                       next_run_date: Time.utc(2026, 7, 31, 9))

    month_end = task(interval_units: 'month', next_run_date: Time.utc(2026, 3, 31, 9))
    result = RedminePeriodictask::IcalImport.parse(export([month_end]), zone: ActiveSupport::TimeZone['UTC'],
                                                                        now: NOW)
    assert_equal [], result.items.first.warnings
    assert_equal '2026-03-31T09:00:00Z', result.items.first.attributes['next_run_date']
  end

  def test_weekdays_follow_the_start_into_the_given_zone
    weekly = task(interval_units: 'week', weekdays: [0, 3], next_run_date: Time.utc(2026, 3, 4, 1)) # Wed 01:00 UTC

    lines = export([weekly], zone: ActiveSupport::TimeZone['Buenos Aires']).split("\r\n") # Tue 22:00 in -03:00
    assert_includes lines, 'DTSTART;TZID=America/Argentina/Buenos_Aires:20260303T220000'
    assert_includes lines, 'RRULE:FREQ=WEEKLY;BYDAY=TU,SA;WKST=MO'

    late = task(interval_units: 'week', weekdays: [6], next_run_date: Time.utc(2026, 3, 7, 23)) # Sat 23:00 UTC
    lines = export([late], zone: ActiveSupport::TimeZone['Tokyo']).split("\r\n") # Sun 08:00 in +09:00
    assert_includes lines, 'RRULE:FREQ=WEEKLY;BYDAY=SU;WKST=MO'
  end

  def test_inactive_task_is_a_cancelled_todo_and_a_task_without_next_run_starts_now
    paused = task(is_active: false)
    paused.update_columns(next_run_date: nil)

    lines = export([paused]).split("\r\n")
    assert_includes lines, 'STATUS:CANCELLED'
    assert_includes lines, "DTSTART:#{NOW.strftime('%Y%m%dT%H%M%SZ')}"
  end

  def test_cancelled_todo_reads_back_as_an_inactive_task
    paused = task(subject: 'Paused', is_active: false)
    running = task(subject: 'Running')

    result = RedminePeriodictask::IcalImport.parse(export([paused, running]), zone: ActiveSupport::TimeZone['UTC'],
                                                                              now: NOW)
    assert_equal false, result.items[0].attributes['is_active']
    assert_nil result.items[1].attributes['is_active']
  end

  def test_long_lines_are_folded_without_splitting_characters
    long = task(subject: "#{'Ñandú ' * 30}end")

    ics = export([long])
    ics.split("\r\n").each { |line| assert_operator line.bytesize, :<=, 75, line }
    assert_equal "SUMMARY:#{'Ñandú ' * 30}end", ics[/SUMMARY:.*?(?=\r\nSTATUS)/m].gsub("\r\n ", '')
  end

  def test_exported_tasks_read_back_as_the_same_schedule
    tasks = [
      task(subject: 'Daily', interval_units: 'day', interval_number: 2),
      task(subject: 'Weekly', interval_units: 'week', weekdays: [1, 4]),
      task(subject: 'Monthly weekday', interval_units: 'month', monthly_mode: 'weekday', weekdays: [1],
           month_weeks: [1, 3]),
      task(subject: 'Monthly day', interval_units: 'month', next_run_date: Time.utc(2026, 3, 15, 8)),
      task(subject: 'Yearly', interval_units: 'year', end_date: Time.utc(2027, 1, 1))
    ]

    result = RedminePeriodictask::IcalImport.parse(export(tasks), zone: ActiveSupport::TimeZone['UTC'], now: NOW)
    assert_equal tasks.map(&:subject), result.items.map(&:subject)
    assert_equal [], result.items.flat_map(&:warnings)
    tasks.zip(result.items).each do |original, item|
      assert_equal "periodictask-#{original.id}@redmine.example.com", item.uid
      assert_equal original.interval_units, item.attributes['interval_units']
      assert_equal original.interval_number, item.attributes['interval_number']
      assert_equal original.weekdays, item.attributes['weekdays']
      assert_equal original.month_weeks, item.attributes['month_weeks']
      assert_equal original.next_run_date.utc.iso8601, Time.iso8601(item.attributes['next_run_date']).utc.iso8601
      if original.end_date
        assert_equal original.end_date.utc.iso8601, Time.iso8601(item.attributes['end_date']).utc.iso8601
      else
        assert_nil item.attributes['end_date']
      end
    end
    assert_equal 'weekday', result.items[2].attributes['monthly_mode']
  end

  private

  def task(attrs = {})
    Periodictask.create!({ project: @project, tracker_id: 1, author_id: 2, subject: 'Test task', interval_number: 1,
                           interval_units: 'month', next_run_date: Time.utc(2026, 4, 1, 9) }.merge(attrs))
  end

  def export(tasks, zone: ActiveSupport::TimeZone['UTC'])
    RedminePeriodictask::IcalExport.export(tasks, zone: zone, now: NOW)
  end

  def rrule(attrs)
    RedminePeriodictask::IcalExport.new([], zone: nil, now: NOW).rrule(task(attrs))
  end
end
