require "#{File.dirname(__FILE__)}/../test_helper"

# Reading of crontab job lines onto the schedule of a periodic task: the
# five time fields, the @shortcuts, comments as description, and the first
# run computed from "now" since cron has no start date. The rule mapping
# itself is shared with the iCalendar import and covered there.
class CronImportTest < ActiveSupport::TestCase
  # A Sunday.
  NOW = Time.utc(2026, 3, 1, 12, 0, 0)

  def test_reads_jobs_and_skips_comments_blank_and_environment_lines
    result = parse(<<~CRON)
      # Nightly jobs
      MAILTO=ops@example.com
      SHELL=/bin/sh

      # Rotate the logs
      # (keeps 7 days)
      0 2 * * *  /usr/local/bin/rotate-logs

      @weekly /usr/local/bin/weekly-report
      @reboot /usr/local/bin/warm-cache
    CRON

    assert_equal 1, result.not_recurring
    assert_empty result.unsupported
    assert_equal ['/usr/local/bin/rotate-logs', '/usr/local/bin/weekly-report'], result.items.map(&:subject)

    rotate, weekly = result.items
    assert_equal "Rotate the logs\n(keeps 7 days)", rotate.description
    assert_equal '0 2 * * *', rotate.rule
    assert_equal 'day', rotate.attributes['interval_units']
    assert_equal Time.utc(2026, 3, 2, 2, 0, 0), Time.iso8601(rotate.attributes['next_run_date'])
    assert_empty rotate.warnings

    assert_nil weekly.description
    assert_equal '@weekly', weekly.rule
    assert_equal 'week', weekly.attributes['interval_units']
    assert_equal [0], weekly.attributes['weekdays']
    assert_equal Time.utc(2026, 3, 8, 0, 0, 0), Time.iso8601(weekly.attributes['next_run_date'])
  end

  def test_uid_is_stable_for_the_same_job
    first = parse("0 9 * * 1 backup\n").items.first
    again = parse("# with a comment\n0 9 * * 1   backup\n").items.first
    other = parse("0 9 * * 2 backup\n").items.first
    assert_equal first.uid, again.uid
    refute_equal first.uid, other.uid
  end

  def test_the_first_run_is_the_next_time_the_job_runs
    daily = parse("30 11 * * * early\n15 13 * * * late\n").items
    assert_equal Time.utc(2026, 3, 2, 11, 30, 0), Time.iso8601(daily[0].attributes['next_run_date'])
    assert_equal Time.utc(2026, 3, 1, 13, 15, 0), Time.iso8601(daily[1].attributes['next_run_date'])

    paris = parse("0 9 * * * bonjour\n", zone: ActiveSupport::TimeZone['Europe/Paris']).items.first
    assert_equal '2026-03-02T09:00:00+01:00', paris.attributes['next_run_date']
  end

  def test_weekly_from_the_day_of_week_field
    item = parse("0 9 * * mon-fri standup\n").items.first
    assert_equal 'week', item.attributes['interval_units']
    assert_equal [1, 2, 3, 4, 5], item.attributes['weekdays']
    assert_equal Time.utc(2026, 3, 2, 9, 0, 0), Time.iso8601(item.attributes['next_run_date'])

    item = parse("0 9 * * 7,3 sunday-and-wednesday\n").items.first
    assert_equal [0, 3], item.attributes['weekdays']

    item = parse("0 9 * * */2 every-other-day-of-week\n").items.first
    assert_equal [0, 2, 4, 6], item.attributes['weekdays']
  end

  def test_monthly_from_the_day_of_month_field
    item = parse("0 9 15 * * invoices\n").items.first
    assert_equal 'month', item.attributes['interval_units']
    assert_nil item.attributes['monthly_mode']
    assert_equal Time.utc(2026, 3, 15, 9, 0, 0), Time.iso8601(item.attributes['next_run_date'])
    assert_empty item.warnings

    item = parse("0 9 1,15 * * twice-a-month\n").items.first
    assert_equal Time.utc(2026, 4, 1, 9, 0, 0), Time.iso8601(item.attributes['next_run_date'])
    assert_equal [{ 'key' => 'part_ignored', 'part' => 'BYMONTHDAY=15' }], item.warnings

    item = parse("0 9 31 * * end-of-long-months\n").items.first
    assert_equal Time.utc(2026, 3, 31, 9, 0, 0), Time.iso8601(item.attributes['next_run_date'])
  end

  def test_yearly_from_the_month_and_day_of_month_fields
    item = parse("0 9 1 jan * new-year\n").items.first
    assert_equal 'year', item.attributes['interval_units']
    assert_equal Time.utc(2027, 1, 1, 9, 0, 0), Time.iso8601(item.attributes['next_run_date'])
    assert_empty item.warnings

    item = parse("0 9 1 1,7 * twice-a-year\n").items.first
    assert_equal Time.utc(2027, 1, 1, 9, 0, 0), Time.iso8601(item.attributes['next_run_date'])
    assert_equal [{ 'key' => 'part_ignored', 'part' => 'BYMONTH=7' }], item.warnings
  end

  def test_restrictions_without_a_counterpart_are_reported
    item = parse("0 9 * jun-aug * summer-daily\n").items.first
    assert_equal 'day', item.attributes['interval_units']
    assert_equal [{ 'key' => 'part_ignored', 'part' => 'BYMONTH=6,7,8' }], item.warnings

    item = parse("0 9 1 * mon first-or-mondays\n").items.first
    assert_equal 'month', item.attributes['interval_units']
    assert_equal [{ 'key' => 'part_ignored', 'part' => 'dow=1' }], item.warnings
  end

  def test_jobs_running_more_than_once_a_day_are_unsupported
    result = parse("*/15 * * * * poll\n0 9,17 * * * twice\n@hourly hourly\n0 * * * * every-hour\n")
    assert_empty result.items
    assert_equal %w[poll twice hourly every-hour], result.unsupported
  end

  def test_long_commands_are_cut_for_the_subject_and_kept_in_the_description
    command = "/usr/bin/env FOO=bar #{'x' * 300}"
    item = parse("0 9 * * * #{command}\n").items.first
    assert_equal 255, item.subject.length
    assert_equal command, item.description
  end

  def test_not_a_crontab
    ["BEGIN:VCALENDAR\nEND:VCALENDAR\n", '{"@type": "Task"}', "0 9 * * *\n", "60 9 * * * bad-minute\n",
     "0 9 * * 8 bad-dow\n", "0 9 * foo * bad-month\n", "0 9 5-1 * * bad-range\n", "@fortnightly x\n"].each do |text|
      assert_raises(RedminePeriodictask::CalendarImport::InvalidFile, text) { parse(text) }
    end
    assert_empty parse("# only comments\n\nMAILTO=root\n").items
  end

  def test_items_make_valid_periodic_tasks
    item = parse("0 9 * * mon-fri standup\n").items.first
    task = Periodictask.new(item.attributes.merge('subject' => item.subject, 'project_id' => 1, 'tracker_id' => 1,
                                                  'author_id' => 1))
    task.valid?
    assert_empty task.errors.select { |e| e.attribute == :base }.map(&:message)
    assert_equal Time.utc(2026, 3, 2, 9, 0, 0), task.next_run_date
  end

  def test_commented_out_jobs_become_inactive_tasks
    text = "# On hold\n# 0 9 * * 1 report\n\n# Runs 0 9 * * 1 too, but not a job\n# @reboot not a job either\n" \
           "0 9 * * * daily\n# @weekly cleanup\n"
    result = parse(text)

    assert_equal %w[report daily cleanup], result.items.map(&:subject)
    assert_equal([false, nil, false], result.items.map { |i| i.attributes['is_active'] })
    assert_equal 'On hold', result.items[0].description
    assert_equal 'week', result.items[0].attributes['interval_units']
    assert_equal "Runs 0 9 * * 1 too, but not a job\n@reboot not a job either", result.items[1].description
    assert_empty result.unsupported
  end

  def test_escaped_percent_signs_are_read_as_percent_signs
    result = parse("0 9 * * * 100\\% done \\%s\n@daily 50% plain\n")

    assert_equal ['100% done %s', '50% plain'], result.items.map(&:subject)
  end

  private

  def parse(text, zone: ActiveSupport::TimeZone['UTC'])
    RedminePeriodictask::CronImport.parse(text, zone: zone, now: NOW)
  end
end
