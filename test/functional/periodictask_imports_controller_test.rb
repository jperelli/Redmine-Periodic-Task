require "#{File.dirname(__FILE__)}/../test_helper"

# Calendar import: upload stages the recurring items, the triage table lets
# an administrator pick a project per row, "create" turns the rows with a
# project into periodic tasks and leaves the others staged.
class PeriodictaskImportsControllerTest < Redmine::IntegrationTest
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :enumerations, :issue_categories, :workflows

  CALENDAR = <<~ICS.freeze
    BEGIN:VCALENDAR
    VERSION:2.0
    BEGIN:VTODO
    UID:todo-weekly
    SUMMARY:Weekly backup check
    DESCRIPTION:Check the backups
    DTSTART:20260302T090000Z
    RRULE:FREQ=WEEKLY;BYDAY=MO
    END:VTODO
    BEGIN:VTODO
    UID:todo-monthly
    SUMMARY:Monthly report
    DTSTART:20260301T100000Z
    RRULE:FREQ=MONTHLY;BYDAY=1MO;BYSETPOS=-2
    END:VTODO
    BEGIN:VTODO
    UID:todo-once
    SUMMARY:Not recurring
    END:VTODO
    END:VCALENDAR
  ICS

  def setup
    Periodictask.delete_all
    PeriodictaskImport.delete_all
    EnabledModule.create!(project_id: 1, name: 'periodictask')
    EnabledModule.create!(project_id: 2, name: 'periodictask')
  end

  teardown do
    I18n.locale = :en
    User.current = nil
  end

  def test_index_shows_the_upload_form_and_an_empty_state
    log_user('admin', 'admin')
    get '/admin/periodictask_imports'
    assert_response :success
    assert_select 'form.periodictask-import-upload' do
      assert_select '.drdn-trigger', text: /Import/
      assert_select 'a.periodictask-import-format[data-source=ical]', text: 'iCalendar (.ics)'
      assert_select 'a.periodictask-import-format[data-source=jscal]', text: 'JSCalendar (.json)'
      assert_select 'a.periodictask-import-format[data-source=cron]', text: 'Crontab (.txt)'
      assert_select 'input[type=file][name=file][data-source=ical][accept=?][disabled]', '.ics,text/calendar'
      assert_select 'input[type=file][name=file][data-source=jscal][disabled]'
      assert_select 'input[type=file][name=file][data-source=cron][accept=?][disabled]',
                    '.cron,.crontab,.txt,text/plain'
      assert_select 'input[type=hidden][name=source]'
      assert_select 'input[type=submit][disabled]'
    end
    assert_select 'p.nodata'
    assert_select 'form#periodictask-import-form', 0
  end

  def test_admin_page_links_to_the_import
    log_user('admin', 'admin')
    get '/admin/periodictasks'
    assert_select 'div.contextual a[href=?]', '/admin/periodictask_imports'
  end

  def test_upload_stages_recurring_items_and_lists_them
    log_user('admin', 'admin')
    post '/admin/periodictask_imports', params: { source: 'ical', file: calendar_file }
    assert_redirected_to '/admin/periodictask_imports'

    assert_equal %w[todo-weekly todo-monthly], PeriodictaskImport.sorted.pluck(:uid)
    weekly = PeriodictaskImport.find_by(uid: 'todo-weekly')
    assert_equal 'Weekly backup check', weekly.subject
    assert_equal 'Check the backups', weekly.description
    assert_equal 'week', weekly.task_attributes['interval_units']
    assert_equal [1], weekly.task_attributes['weekdays']
    assert_equal User.find_by_login('admin'), weekly.user
    assert_nil weekly.project

    follow_redirect!
    assert_select 'div.flash.notice', text: /2 recurring item\(s\) staged.*1 item\(s\) without recurrence rule skipped/
    assert_select 'table.periodictask-imports tbody tr', 2
    assert_select 'table.periodictask-imports td.subject', text: /Weekly backup check/
    assert_select 'table.periodictask-imports td.interval', text: /each week on Monday/
    assert_select 'table.periodictask-imports td.interval', text: /each month on the 1st Monday/
    assert_select 'table.periodictask-imports td.periodictask-import-warnings',
                  text: I18n.t(:warning_periodictask_import_part_ignored, part: 'BYSETPOS=-2')
    assert_select "select[name='project_ids[#{weekly.id}]']" do
      assert_select 'option[value=""]'
      assert_select 'option[value="1"]', text: 'eCookbook'
      assert_select 'option[value="3"]', 0, 'projects without the module are not offered'
    end
    assert_select 'form#periodictask-import-form input[type=submit][value=?]', 'Create periodic tasks'
  end

  def test_upload_does_not_stage_the_same_uid_twice
    log_user('admin', 'admin')
    post '/admin/periodictask_imports', params: { source: 'ical', file: calendar_file }
    post '/admin/periodictask_imports', params: { source: 'ical', file: calendar_file }
    follow_redirect!

    assert_equal 2, PeriodictaskImport.count
    assert_select 'div.flash.notice', text: /0 recurring item\(s\) staged. 2 already staged and skipped/
  end

  def test_upload_without_a_file_is_an_error
    log_user('admin', 'admin')
    post '/admin/periodictask_imports', params: { source: 'ical' }
    assert_redirected_to '/admin/periodictask_imports'
    follow_redirect!
    assert_select 'div.flash.error', text: I18n.t(:error_periodictask_import_no_file)
    assert_equal 0, PeriodictaskImport.count
  end

  def test_upload_without_a_format_is_an_error
    log_user('admin', 'admin')
    post '/admin/periodictask_imports', params: { file: calendar_file }
    follow_redirect!
    assert_select 'div.flash.error', text: I18n.t(:error_periodictask_import_no_format)
    assert_equal 0, PeriodictaskImport.count
  end

  def test_upload_of_a_jscalendar_file_stages_its_items
    log_user('admin', 'admin')
    post '/admin/periodictask_imports', params: { source: 'jscal', file: jscalendar_file }
    assert_redirected_to '/admin/periodictask_imports'

    assert_equal %w[jscal-weekly], PeriodictaskImport.pluck(:uid)
    weekly = PeriodictaskImport.first
    assert_equal 'jscal', weekly.source
    assert_equal 'Weekly backup check (JSCalendar)', weekly.subject
    assert_equal 'week', weekly.task_attributes['interval_units']
    assert_equal [1], weekly.task_attributes['weekdays']

    follow_redirect!
    assert_select 'div.flash.notice', text: /1 recurring item\(s\) staged.*1 item\(s\) without recurrence rule skipped/
    assert_select 'table.periodictask-imports td.interval', text: /each week on Monday/
  end

  def test_upload_in_the_wrong_format_is_an_error
    log_user('admin', 'admin')
    post '/admin/periodictask_imports', params: { source: 'jscal', file: calendar_file }
    follow_redirect!
    assert_select 'div.flash.error',
                  text: I18n.t(:error_periodictask_import_invalid_file, format_name: 'JSCalendar (.json)')

    post '/admin/periodictask_imports', params: { source: 'ical', file: jscalendar_file }
    follow_redirect!
    assert_select 'div.flash.error',
                  text: I18n.t(:error_periodictask_import_invalid_file, format_name: 'iCalendar (.ics)')

    post '/admin/periodictask_imports', params: { source: 'cron', file: calendar_file }
    follow_redirect!
    assert_select 'div.flash.error',
                  text: I18n.t(:error_periodictask_import_invalid_file, format_name: 'Crontab (.txt)')
    assert_equal 0, PeriodictaskImport.count
  end

  def test_upload_of_a_crontab_stages_its_jobs
    log_user('admin', 'admin')
    post '/admin/periodictask_imports', params: { source: 'cron', file: crontab_file }
    assert_redirected_to '/admin/periodictask_imports'

    assert_equal ['/usr/local/bin/backup --full'], PeriodictaskImport.pluck(:subject)
    job = PeriodictaskImport.first
    assert_equal 'cron', job.source
    assert_match(/\Acron:\h{40}\z/, job.uid)
    assert_equal 'Full backup', job.description
    assert_equal 'week', job.task_attributes['interval_units']
    assert_equal [1, 4], job.task_attributes['weekdays']

    follow_redirect!
    assert_select 'div.flash.notice', text: /1 recurring item\(s\) staged.*1 item\(s\) without recurrence rule skipped/
    assert_select 'div.flash.notice', text: %r{more often than daily skipped: /usr/local/bin/poll}
    assert_select 'table.periodictask-imports td.interval[title=?]', '0 3 * * 1,4'

    post '/admin/periodictask_imports', params: { source: 'cron', file: crontab_file }
    assert_equal 1, PeriodictaskImport.count
  end

  def test_the_same_uid_is_not_staged_twice_across_formats
    log_user('admin', 'admin')
    post '/admin/periodictask_imports', params: { source: 'ical', file: calendar_file }
    post '/admin/periodictask_imports', params: { source: 'jscal', file: jscalendar_file('uid' => 'todo-weekly') }
    follow_redirect!

    assert_equal %w[todo-weekly todo-monthly], PeriodictaskImport.sorted.pluck(:uid)
    assert_equal %w[ical], PeriodictaskImport.distinct.pluck(:source)
    assert_select 'div.flash.notice', text: /0 recurring item\(s\) staged. 1 already staged and skipped/
  end

  def test_create_imports_the_rows_with_a_project_and_keeps_the_others
    weekly, monthly = stage_calendar

    log_user('admin', 'admin')
    assert_difference 'Periodictask.count', 1 do
      post '/admin/periodictask_imports/import',
           params: { project_ids: { weekly.id.to_s => '2', monthly.id.to_s => '' } }
    end
    assert_redirected_to '/admin/periodictask_imports'

    task = Periodictask.last
    assert_equal 2, task.project_id
    assert_equal 'Weekly backup check', task.subject
    assert_equal 'Check the backups', task.description
    assert_equal 'week', task.interval_units
    assert_equal [1], task.weekdays
    assert_equal Project.find(2).trackers.first, task.tracker
    assert_equal User.find_by_login('admin'), task.author
    assert task.next_run_date > Time.current, 'a first run in the past moves to the next occurrence'
    assert_equal 1, task.next_run_date.wday
    assert_equal 9, task.next_run_date.utc.hour
    assert_equal 1, PeriodictaskJournal.where(periodictask_id: task.id).count

    assert_equal [monthly.id], PeriodictaskImport.pluck(:id)
    follow_redirect!
    assert_select 'div.flash.notice', text: I18n.t(:notice_periodictask_import_created, count: 1)
    assert_select 'table.periodictask-imports tbody tr', 1
    assert_select 'table.periodictask-imports td.subject', text: /Monthly report/
  end

  def test_create_without_any_project_chosen_changes_nothing
    weekly, monthly = stage_calendar

    log_user('admin', 'admin')
    assert_no_difference 'Periodictask.count' do
      post '/admin/periodictask_imports/import',
           params: { project_ids: { weekly.id.to_s => '', monthly.id.to_s => '' } }
    end
    assert_equal 2, PeriodictaskImport.count
    follow_redirect!
    assert_select 'div.flash.warning', text: I18n.t(:notice_periodictask_import_nothing_selected)
  end

  def test_create_keeps_a_failed_row_with_the_reason
    weekly, = stage_calendar

    log_user('admin', 'admin')
    assert_no_difference 'Periodictask.count' do
      post '/admin/periodictask_imports/import', params: { project_ids: { weekly.id.to_s => '3' } }
    end
    weekly.reload
    assert_equal 3, weekly.project_id
    assert_equal I18n.t(:error_periodictask_import_project_not_allowed), weekly.last_error

    follow_redirect!
    assert_select 'div.flash.error', text: I18n.t(:error_periodictask_import_failed, count: 1)
    assert_select 'tr.periodictask-import-failed td.subject div.periodictask-import-error',
                  text: I18n.t(:error_periodictask_import_project_not_allowed)
  end

  def test_create_reports_an_invalid_generated_issue
    weekly, = stage_calendar
    Project.find(2).trackers.clear

    log_user('admin', 'admin')
    assert_no_difference 'Periodictask.count' do
      post '/admin/periodictask_imports/import', params: { project_ids: { weekly.id.to_s => '2' } }
    end
    assert_match(/Tracker/, weekly.reload.last_error)
  end

  def test_destroy_discards_a_row
    weekly, monthly = stage_calendar

    log_user('admin', 'admin')
    delete "/admin/periodictask_imports/#{weekly.id}"
    assert_redirected_to '/admin/periodictask_imports'
    assert_equal [monthly.id], PeriodictaskImport.pluck(:id)
  end

  def test_destroy_unknown_row_is_not_found
    log_user('admin', 'admin')
    delete '/admin/periodictask_imports/999'
    assert_response :not_found
  end

  def test_flash_uses_the_admin_locale
    User.find_by_login('admin').update!(language: 'es')

    log_user('admin', 'admin')
    post '/admin/periodictask_imports', params: { source: 'ical', file: calendar_file }
    follow_redirect!
    expected = I18n.t(:notice_periodictask_import_staged, count: 2, locale: :es)
    assert_select 'div.flash.notice', text: /#{Regexp.escape(expected)}/
  end

  def test_non_admin_is_forbidden
    weekly, = stage_calendar

    log_user('jsmith', 'jsmith')
    get '/admin/periodictask_imports'
    assert_response :forbidden
    post '/admin/periodictask_imports', params: { source: 'ical', file: calendar_file }
    assert_response :forbidden
    post '/admin/periodictask_imports/import', params: { project_ids: { weekly.id.to_s => '1' } }
    assert_response :forbidden
    delete "/admin/periodictask_imports/#{weekly.id}"
    assert_response :forbidden
    assert_equal 2, PeriodictaskImport.count
    assert_equal 0, Periodictask.count
  end

  def test_anonymous_is_redirected_to_login
    get '/admin/periodictask_imports'
    assert_response :redirect
    post '/admin/periodictask_imports', params: { source: 'ical', file: calendar_file }
    assert_response :redirect
    assert_equal 0, PeriodictaskImport.count
  end

  private

  def calendar_file
    Rack::Test::UploadedFile.new(StringIO.new(CALENDAR), 'text/calendar', original_filename: 'tasks.ics')
  end

  def crontab_file
    crontab = <<~CRON
      MAILTO=root
      # Full backup
      0 3 * * 1,4 /usr/local/bin/backup --full
      */5 * * * * /usr/local/bin/poll
      @reboot /usr/local/bin/warm-cache
    CRON
    Rack::Test::UploadedFile.new(StringIO.new(crontab), 'text/plain', original_filename: 'crontab.txt')
  end

  def jscalendar_file(overrides = {})
    weekly = { '@type' => 'Task', 'uid' => 'jscal-weekly', 'title' => 'Weekly backup check (JSCalendar)',
               'start' => '2026-03-02T09:00:00', 'timeZone' => 'Etc/UTC',
               'recurrenceRules' => [{ '@type' => 'RecurrenceRule', 'frequency' => 'weekly',
                                       'byDay' => [{ '@type' => 'NDay', 'day' => 'mo' }] }] }.merge(overrides)
    once = { '@type' => 'Task', 'uid' => 'jscal-once', 'title' => 'Not recurring' }
    group = { '@type' => 'Group', 'uid' => 'jscal-group', 'entries' => [weekly, once] }
    Rack::Test::UploadedFile.new(StringIO.new(JSON.generate(group)), 'application/json',
                                 original_filename: 'tasks.json')
  end

  def stage_calendar
    result = RedminePeriodictask::IcalImport.parse(CALENDAR)
    PeriodictaskImport.stage(result.items, source: 'ical', user: User.find_by_login('admin'))
    PeriodictaskImport.sorted.to_a
  end
end
