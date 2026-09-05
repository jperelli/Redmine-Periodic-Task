require "#{File.dirname(__FILE__)}/../test_helper"

class PeriodictaskSettingsTest < Redmine::IntegrationTest
  fixtures :users, :email_addresses, :roles

  def setup
    log_user('admin', 'admin')
  end

  def teardown
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
  end

  def test_plugin_settings_can_switch_to_web_mode
    post '/settings/plugin/periodictask', params: { settings: { scheduler_mode: 'web', web_check_interval: '15' } }
    assert_redirected_to '/settings/plugin/periodictask'
    assert_equal 'web', Setting.plugin_periodictask['scheduler_mode']
    assert RedminePeriodictask::WebScheduler.enabled?
    assert_equal 15.minutes, RedminePeriodictask::WebScheduler.interval
  end
end
