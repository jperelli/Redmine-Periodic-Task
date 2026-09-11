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

  def test_runs_the_checker
    ScheduledTasksChecker.expects(:checktasks!).once
    Rake::Task['redmine:check_periodictasks'].invoke
  end

  def test_aborts_with_an_explanation_when_the_plugin_is_not_loaded
    Redmine::Plugin.stubs(:installed?).with(:periodictask).returns(false)
    ScheduledTasksChecker.expects(:checktasks!).never

    _out, err = capture_io do
      assert_raises(SystemExit) { Rake::Task['redmine:check_periodictasks'].invoke }
    end
    assert_match(/periodictask plugin is not loaded/, err)
    assert_match(Regexp.escape(Redmine::PluginLoader.directory.to_s), err)
    assert_match(/Redmine-Periodic-Task#installation/, err)
  end
end
