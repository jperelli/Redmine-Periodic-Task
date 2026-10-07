require "#{File.dirname(__FILE__)}/../test_helper"
require 'rake'

class CheckPeriodictasksRakeTest < ActiveSupport::TestCase
  RAKEFILE = File.expand_path('../../lib/tasks/periodictask.rake', __dir__)

  def setup
    @previous_application = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    Rake.load_rakefile(RAKEFILE)
  end

  def teardown
    Rake.application = @previous_application
  end

  def test_runs_the_checker_and_prints_a_summary_even_when_nothing_was_due
    ScheduledTasksChecker.expects(:run!).once.returns(result(0, 0))

    out, err = capture_io { Rake::Task['redmine:check_periodictasks'].invoke }
    assert_match(/periodictask: 0 task\(s\) due, 0 issue\(s\) created$/, out)
    assert_empty err
  end

  def test_summary_counts_the_created_issues
    ScheduledTasksChecker.stubs(:run!).returns(result(3, 2))

    out, _err = capture_io { Rake::Task['redmine:check_periodictasks'].invoke }
    assert_match(/periodictask: 3 task\(s\) due, 2 issue\(s\) created$/, out)
  end

  def test_errors_are_counted_on_stdout_and_listed_on_stderr
    ScheduledTasksChecker.stubs(:run!).returns(result(2, 1, ['#7 Backup: boom']))

    out, err = capture_io { Rake::Task['redmine:check_periodictasks'].invoke }
    assert_match(/2 task\(s\) due, 1 issue\(s\) created, 1 error\(s\)$/, out)
    assert_match(/periodictask: error: #7 Backup: boom$/, err)
  end

  def test_aborts_with_an_explanation_when_the_plugin_is_not_loaded
    Redmine::Plugin.stubs(:installed?).with(:periodictask).returns(false)
    ScheduledTasksChecker.expects(:run!).never

    _out, err = capture_io do
      assert_raises(SystemExit) { Rake::Task['redmine:check_periodictasks'].invoke }
    end
    assert_match(/periodictask plugin is not loaded/, err)
    assert_match(Regexp.escape(Redmine::PluginLoader.directory.to_s), err)
    assert_match(/Redmine-Periodic-Task#installation/, err)
  end

  def test_checktasks_still_returns_the_number_of_due_tasks
    ScheduledTasksChecker.stubs(:run!).with(source: 'manual').returns(result(4, 1))
    assert_equal 4, ScheduledTasksChecker.checktasks!(source: 'manual')
  end

  private

  def result(tasks_due, issues_created, errors = [])
    ScheduledTasksChecker::Result.new(tasks_due: tasks_due, issues_created: issues_created, errors: errors, notes: [])
  end
end
