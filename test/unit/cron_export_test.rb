require "#{File.dirname(__FILE__)}/../test_helper"

# Periodic tasks written as crontab job lines, and read back by the importer
# as the same schedule.
class CronExportTest < ActiveSupport::TestCase
  fixtures :projects, :users, :trackers, :enumerations

  NOW = Time.utc(2026, 3, 1, 12, 0, 0)

  def setup
    Periodictask.delete_all
    @project = Project.find(1)
    Setting.host_name = 'redmine.example.com'
  end

  def test_writes_one_job_per_task_with_the_description_as_comments
    daily = task(subject: "Water  the\nplants", description: "Every single day\n\nreally",
                 interval_units: 'day', next_run_date: Time.utc(2026, 3, 5, 9, 30))
    weekly = task(subject: 'Weekly sync', interval_units: 'week', weekdays: [1, 3],
                  next_run_date: Time.utc(2026, 3, 2, 9))

    text = export([daily, weekly])
    assert text.end_with?("\n")
    assert_equal ['# Redmine periodic tasks, 2026-03-01 12:00 UTC',
                  '# m h dom mon dow  task',
                  '',
                  '# Every single day',
                  '#',
                  '# really',
                  '30 9 * * *  Water the plants',
                  '',
                  '0 9 * * 1,3  Weekly sync'], text.split("\n")
  end

  def test_schedule_per_interval
    assert_equal '0 9 * * *', schedule(interval_units: 'day')
    assert_equal '0 9 * * 1,2,3,4,5', schedule(interval_units: 'business_day')
    with_settings non_working_week_days: %w[5 6 7] do
      assert_equal '0 9 * * 1,2,3,4', schedule(interval_units: 'business_day')
    end
    assert_equal '0 9 * * 1,3', schedule(interval_units: 'week', weekdays: [1, 3])
    assert_equal '0 9 * * 3', schedule(interval_units: 'week', weekdays: []), 'the weekday of the next run'
    assert_equal '0 9 1 * *', schedule(interval_units: 'month')
    assert_equal '0 9 1 4 *', schedule(interval_units: 'year')
    assert_equal '0 9 8 * *',
                 schedule(interval_units: 'month', monthly_mode: 'weekday', weekdays: [3], month_weeks: [2],
                          next_run_date: Time.utc(2026, 4, 8, 9)),
                 'the day of the month of the next run stands in for the nth weekday'
  end

  def test_times_are_in_the_given_zone
    monthly = task(interval_units: 'month', next_run_date: Time.utc(2026, 4, 1, 1)) # Mar 31 22:00 in -03:00

    text = export([monthly], zone: ActiveSupport::TimeZone['Buenos Aires'])
    assert_includes text.split("\n"), '0 22 31 * *  Test task'
    assert_includes text, '# Redmine periodic tasks, 2026-03-01 09:00 -03'
  end

  def test_what_cron_cannot_say_is_noted_above_the_job
    lines = export([task(interval_units: 'day', interval_number: 2, end_date: Time.utc(2026, 12, 31, 23)),
                    task(interval_units: 'month', monthly_mode: 'weekday', weekdays: [1], month_weeks: [2],
                         max_occurrences: 10, occurrences_count: 3),
                    task(interval_units: 'day', end_date: Time.utc(2026, 12, 31, 23), max_occurrences: 10)]).split("\n")

    assert_includes lines, '# Not carried over: interval=2, end_date=2026-12-31'
    assert_includes lines, '# Not carried over: monthly_mode=weekday, max_occurrences=7'
    assert_includes lines, '# Not carried over: end_date=2026-12-31, max_occurrences=10'
  end

  def test_inactive_task_is_a_commented_out_job_and_a_task_without_next_run_starts_now
    paused = task(subject: 'Paused', is_active: false)
    paused.update_columns(next_run_date: nil)

    lines = export([paused]).split("\n")
    assert_includes lines, '# 0 12 1 * *  Paused'
  end

  def test_ended_task_is_a_commented_out_job
    done = task(subject: 'Done', max_occurrences: 3, occurrences_count: 3)

    lines = export([done]).split("\n")
    assert_includes lines, '# Not carried over: max_occurrences=0'
    assert_includes lines, '# 0 9 1 * *  Done'
  end

  def test_exported_tasks_read_back_as_the_same_schedule
    tasks = [
      task(subject: 'Daily', description: "Water\nthe plants", interval_units: 'day',
           next_run_date: Time.utc(2026, 3, 2, 9)),
      task(subject: 'Business days', interval_units: 'business_day', next_run_date: Time.utc(2026, 3, 2, 9)),
      task(subject: 'Weekly', interval_units: 'week', weekdays: [1, 4], next_run_date: Time.utc(2026, 3, 2, 9)),
      task(subject: 'Monthly day', interval_units: 'month', next_run_date: Time.utc(2026, 3, 15, 8)),
      task(subject: 'Yearly', interval_units: 'year', next_run_date: Time.utc(2026, 6, 1, 7))
    ]
    zone = ActiveSupport::TimeZone['UTC']

    # Cron has no first-run date: the importer takes the next time the job runs after +now+, so the tasks above
    # are due at exactly that time.
    result = RedminePeriodictask::CronImport.parse(export(tasks, zone: zone), zone: zone, now: NOW)
    assert_equal tasks.map(&:subject), result.items.map(&:subject)
    assert_equal [], result.items.flat_map(&:warnings)
    assert_equal "Water\nthe plants", result.items.first.description
    tasks.zip(result.items).each do |original, item|
      expected_units = original.interval_units == 'business_day' ? 'week' : original.interval_units
      expected_weekdays = original.interval_units == 'business_day' ? [1, 2, 3, 4, 5] : original.weekdays
      assert_equal expected_units, item.attributes['interval_units']
      assert_equal expected_weekdays, item.attributes['weekdays']
      assert_equal original.next_run_date.utc.iso8601, Time.iso8601(item.attributes['next_run_date']).utc.iso8601
    end
  end

  private

  def task(attrs = {})
    Periodictask.create!({ project: @project, tracker_id: 1, author_id: 2, subject: 'Test task', interval_number: 1,
                           interval_units: 'month', next_run_date: Time.utc(2026, 4, 1, 9) }.merge(attrs))
  end

  def export(tasks, zone: ActiveSupport::TimeZone['UTC'])
    RedminePeriodictask::CronExport.export(tasks, zone: zone, now: NOW)
  end

  def schedule(attrs)
    RedminePeriodictask::CronExport.new([], zone: nil).schedule(task(attrs))
  end
end
