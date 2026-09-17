require "#{File.dirname(__FILE__)}/../test_helper"

# Periodic tasks written as JSCalendar Tasks with a RecurrenceRule, and read
# back by the importer as the same schedule.
class JscalExportTest < ActiveSupport::TestCase
  fixtures :projects, :users, :trackers, :enumerations

  NOW = Time.utc(2026, 3, 1, 12, 0, 0)

  def setup
    Periodictask.delete_all
    @project = Project.find(1)
    Setting.host_name = 'redmine.example.com'
    Setting.protocol = 'https'
    Setting.start_of_week = '1'
  end

  def test_writes_a_group_with_one_task_per_periodic_task
    daily = task(subject: 'Water the plants', description: "Every, single\nday", interval_units: 'day',
                 interval_number: 2, next_run_date: Time.utc(2026, 3, 5, 9))
    weekly = task(subject: 'Weekly sync', interval_units: 'week', weekdays: [1, 3],
                  next_run_date: Time.utc(2026, 3, 2, 9), tag_list: 'ops, team')

    json = export([daily, weekly])
    assert json.end_with?("\n")
    group = JSON.parse(json)

    assert_equal 'Group', group['@type']
    assert_equal '-//Redmine Periodic Task//EN', group['prodId']
    assert_equal '2026-03-01T12:00:00Z', group['updated']
    assert_equal 2, group['entries'].size

    first, second = group['entries']
    assert_equal 'Task', first['@type']
    assert_equal "periodictask-#{daily.id}@redmine.example.com", first['uid']
    assert_equal '2026-03-01T12:00:00Z', first['updated']
    assert_equal 'Water the plants', first['title']
    assert_equal "Every, single\nday", first['description']
    assert_equal '2026-03-05T09:00:00', first['start']
    assert_equal 'Etc/UTC', first['timeZone']
    assert_equal [{ '@type' => 'RecurrenceRule', 'frequency' => 'daily', 'interval' => 2 }], first['recurrenceRules']
    assert_equal 'needs-action', first['progress']
    link = "https://redmine.example.com/projects/ecookbook/periodictask/#{daily.id}"
    assert_equal({ 'redmine' => { '@type' => 'Link', 'rel' => 'alternate', 'href' => link } }, first['links'])
    assert_not first.key?('keywords')

    assert_equal [{ '@type' => 'RecurrenceRule', 'frequency' => 'weekly', 'firstDayOfWeek' => 'mo',
                    'byDay' => [{ '@type' => 'NDay', 'day' => 'mo' }, { '@type' => 'NDay', 'day' => 'we' }] }],
                 second['recurrenceRules']
    assert_equal({ 'ops' => true, 'team' => true }, second['keywords'])
    assert_not second.key?('description')
  end

  def test_start_and_until_are_local_times_in_the_given_zone
    weekly = task(interval_units: 'week', weekdays: [2], next_run_date: Time.utc(2026, 3, 3, 1),
                  end_date: Time.utc(2026, 12, 31, 23)) # Tue 01:00 UTC = Mon 22:00 in -03:00

    entry = JSON.parse(export([weekly], zone: ActiveSupport::TimeZone['Buenos Aires']))['entries'].first
    assert_equal '2026-03-02T22:00:00', entry['start']
    assert_equal 'America/Argentina/Buenos_Aires', entry['timeZone']
    assert_equal '2026-12-31T20:00:00', entry['recurrenceRules'].first['until']
  end

  def test_recurrence_rule_per_schedule
    assert_equal({ 'frequency' => 'daily' }, rule(interval_units: 'day'))
    workdays = %w[mo tu we th fr].map { |day| { '@type' => 'NDay', 'day' => day } }
    assert_equal({ 'frequency' => 'daily', 'byDay' => workdays }, rule(interval_units: 'business_day'))
    assert_equal({ 'frequency' => 'weekly', 'interval' => 2 }, rule(interval_units: 'week', interval_number: 2))
    assert_equal({ 'frequency' => 'monthly' }, rule(interval_units: 'month'))
    assert_equal({ 'frequency' => 'monthly',
                   'byDay' => [{ '@type' => 'NDay', 'day' => 'mo', 'nthOfPeriod' => 1 },
                               { '@type' => 'NDay', 'day' => 'mo', 'nthOfPeriod' => 3 }] },
                 rule(interval_units: 'month', monthly_mode: 'weekday', weekdays: [1], month_weeks: [1, 3]))
    assert_equal({ 'frequency' => 'monthly', 'byDay' => [{ '@type' => 'NDay', 'day' => 'fr', 'nthOfPeriod' => -1 }] },
                 rule(interval_units: 'month', monthly_mode: 'weekday', weekdays: [5], month_weeks: [5]))
    assert_equal({ 'frequency' => 'yearly' }, rule(interval_units: 'year'))
    assert_equal({ 'frequency' => 'daily', 'count' => 7 },
                 rule(interval_units: 'day', max_occurrences: 10, occurrences_count: 3))
    assert_equal({ 'frequency' => 'daily', 'count' => 10 },
                 rule(interval_units: 'day', end_date: Time.utc(2026, 12, 31, 23), max_occurrences: 10),
                 'ten daily runs from April end long before December')
    assert_equal({ 'frequency' => 'daily', 'until' => '2026-04-05T23:00:00' },
                 rule(interval_units: 'day', end_date: Time.utc(2026, 4, 5, 23), max_occurrences: 10))
  end

  def test_business_days_follow_the_non_working_days_setting
    with_settings non_working_week_days: %w[6 7 1] do
      days = %w[tu we th fr].map { |day| { '@type' => 'NDay', 'day' => day } }
      assert_equal({ 'frequency' => 'daily', 'byDay' => days }, rule(interval_units: 'business_day'))
    end
  end

  def test_inactive_task_is_cancelled_and_a_task_without_next_run_starts_now
    paused = task(is_active: false)
    paused.update_columns(next_run_date: nil)

    entry = JSON.parse(export([paused]))['entries'].first
    assert_equal 'cancelled', entry['progress']
    assert_equal '2026-03-01T12:00:00', entry['start']
  end

  def test_ended_task_is_completed_without_recurrence_rules
    done = task(max_occurrences: 3, occurrences_count: 3)

    entry = JSON.parse(export([done]))['entries'].first
    assert_equal 'completed', entry['progress']
    assert_nil entry['recurrenceRules']
    assert_equal '2026-04-01T09:00:00', entry['start']
  end

  def test_exported_tasks_read_back_as_the_same_schedule
    tasks = [
      task(subject: 'Daily', interval_units: 'day', interval_number: 2),
      task(subject: 'Business days', interval_units: 'business_day'),
      task(subject: 'Weekly', interval_units: 'week', weekdays: [1, 4]),
      task(subject: 'Monthly weekday', interval_units: 'month', monthly_mode: 'weekday', weekdays: [1],
           month_weeks: [1, 3]),
      task(subject: 'Monthly day', interval_units: 'month', next_run_date: Time.utc(2026, 3, 15, 8)),
      task(subject: 'Yearly', interval_units: 'year', end_date: Time.utc(2027, 1, 1))
    ]
    zone = ActiveSupport::TimeZone['Buenos Aires']

    result = RedminePeriodictask::JscalImport.parse(export(tasks, zone: zone), zone: zone, now: NOW)
    assert_equal tasks.map(&:subject), result.items.map(&:subject)
    assert_equal [], result.items.flat_map(&:warnings)
    tasks.zip(result.items).each do |original, item|
      assert_equal "periodictask-#{original.id}@redmine.example.com", item.uid
      expected_units = original.interval_units == 'business_day' ? 'week' : original.interval_units
      expected_weekdays = original.interval_units == 'business_day' ? [1, 2, 3, 4, 5] : original.weekdays
      assert_equal expected_units, item.attributes['interval_units']
      assert_equal original.interval_number, item.attributes['interval_number']
      assert_equal expected_weekdays, item.attributes['weekdays']
      assert_equal original.month_weeks, item.attributes['month_weeks']
      assert_equal original.next_run_date.utc.iso8601, Time.iso8601(item.attributes['next_run_date']).utc.iso8601
      if original.end_date
        assert_equal original.end_date.utc.iso8601, Time.iso8601(item.attributes['end_date']).utc.iso8601
      else
        assert_nil item.attributes['end_date']
      end
    end
    assert_equal 'weekday', result.items[3].attributes['monthly_mode']
  end

  private

  def task(attrs = {})
    Periodictask.create!({ project: @project, tracker_id: 1, author_id: 2, subject: 'Test task', interval_number: 1,
                           interval_units: 'month', next_run_date: Time.utc(2026, 4, 1, 9) }.merge(attrs))
  end

  def export(tasks, zone: ActiveSupport::TimeZone['UTC'])
    RedminePeriodictask::JscalExport.export(tasks, zone: zone, now: NOW)
  end

  def rule(attrs)
    RedminePeriodictask::JscalExport.new([], zone: nil, now: NOW).recurrence_rule(task(attrs)).except('@type')
  end
end
