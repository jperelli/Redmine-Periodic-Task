require "#{File.dirname(__FILE__)}/../test_helper"

class PeriodictaskSettingsTest < Redmine::IntegrationTest
  fixtures :users, :email_addresses, :roles

  def setup
    Setting.plugin_periodictask = { 'scheduler_mode' => 'cron' }
    RedminePeriodictask::WebScheduler.reset!
    # A checker running in its own thread writes outside the test transaction,
    # so its rows would survive into the next test.
    RedminePeriodictask::WebScheduler.synchronous = true
    log_user('admin', 'admin')
    PeriodictaskRun.delete_all
  end

  def teardown
    RedminePeriodictask::WebScheduler.synchronous = false
    RedminePeriodictask::WebScheduler.reset!
    Setting.plugin_periodictask = { 'scheduler_mode' => 'cron' }
  end

  def test_plugin_settings_page_renders
    get '/settings/plugin/periodictask'
    assert_response :success
    assert_select 'select[name=?]', 'settings[scheduler_mode]' do
      assert_select 'option[value=cron][selected]'
      assert_select 'option[value=web]'
    end
    assert_select 'input[name=?]', 'settings[web_check_interval]'
    assert_select 'code', text: %r{/periodictask/check\?key=}
    assert_select 'a[href=?][data-method=post]', '/admin/periodictask/run_checker'
    assert_select 'p.nodata'
  end

  def test_plugin_settings_page_lists_recent_runs
    PeriodictaskRun.delete_all
    PeriodictaskRun.record!(source: 'endpoint', started_at: 1.minute.ago, finished_at: Time.current,
                            tasks_due: 1, issues_created: 0, errors: ['#1 Foo: Project is missing or closed'])
    get '/settings/plugin/periodictask'
    assert_response :success
    assert_select 'table.periodictask-runs tbody tr.error', 1 do
      assert_select 'td', text: 'Check URL'
      assert_select 'td', text: /Project is missing or closed/
    end
  end

  def test_plugin_settings_can_switch_to_web_mode
    post '/settings/plugin/periodictask', params: { settings: { scheduler_mode: 'web', web_check_interval: '15' } }
    assert_redirected_to '/settings/plugin/periodictask'
    assert_equal 'web', Setting.plugin_periodictask['scheduler_mode']
    assert RedminePeriodictask::WebScheduler.enabled?
    assert_equal 15.minutes, RedminePeriodictask::WebScheduler.interval
  end
end
