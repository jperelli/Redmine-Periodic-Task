require "#{File.dirname(__FILE__)}/../test_helper"

# End condition of a periodic task: an optional end date and/or a maximum
# number of scheduled runs. Whichever is reached first disables the task and
# the reason is written to the activity log.
class EndConditionTest < ActiveSupport::TestCase
  fixtures :projects, :users, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :enabled_modules, :roles, :members, :member_roles

  def setup
    @project = Project.find(1)
    EnabledModule.create!(project: @project, name: 'periodictask')
    User.current = nil
  end

  # ---- validation ----

  def test_end_date_and_max_occurrences_are_optional
    task = build_task
    assert task.valid?
    assert_nil task.end_date
    assert_nil task.max_occurrences
    assert_equal 0, task.occurrences_count
  end

  def test_end_date_must_not_be_before_next_run_date
    anchor = Time.utc(2026, 3, 1, 10, 0, 0)

    assert build_task(next_run_date: anchor, end_date: anchor + 1.minute).valid?
    assert build_task(next_run_date: anchor, end_date: anchor).valid?

    task = build_task(next_run_date: anchor, end_date: anchor - 1.second)
    assert_not task.valid?
    assert_includes task.errors.full_messages, I18n.t(:error_end_date_before_next_run)
  end

  def test_end_date_without_next_run_date_is_accepted
    assert build_task(next_run_date: nil, end_date: 1.year.from_now).valid?
  end

  def test_disabled_task_may_keep_a_next_run_past_its_end_date
    anchor = Time.utc(2026, 3, 1, 10, 0, 0)
    task = build_task(next_run_date: anchor, end_date: anchor - 1.day, is_active: false)

    assert task.valid?
  end

  def test_max_occurrences_must_be_positive
    assert build_task(max_occurrences: 1).valid?

    [0, -1].each do |n|
      task = build_task(max_occurrences: n)
      assert_not task.valid?, "#{n} should be invalid"
      assert_includes task.errors.full_messages, I18n.t(:error_max_occurrences_not_positive)
    end
  end

  # ---- end_reason ----

  def test_end_reason_is_nil_without_end_condition
    assert_nil build_task(next_run_date: 1.day.ago).end_reason
    assert_not build_task(next_run_date: 1.day.ago).end_reached?
  end

  def test_end_reason_by_date_only_when_next_run_is_strictly_after_end_date
    end_date = Time.utc(2026, 3, 1, 10, 0, 0)
    task = build_task(is_active: false, end_date: end_date)

    task.next_run_date = end_date - 1.second
    assert_nil task.end_reason
    task.next_run_date = end_date
    assert_nil task.end_reason
    task.next_run_date = end_date + 1.second
    assert_equal 'ended_by_date', task.end_reason
  end

  def test_end_reason_by_count_when_occurrences_reach_max
    task = build_task(max_occurrences: 3)

    task.occurrences_count = 2
    assert_nil task.end_reason
    task.occurrences_count = 3
    assert_equal 'ended_by_count', task.end_reason
    task.occurrences_count = 4
    assert_equal 'ended_by_count', task.end_reason
  end

  def test_end_reason_prefers_count_when_both_conditions_are_met
    task = build_task(is_active: false, max_occurrences: 1, occurrences_count: 1,
                      end_date: Time.utc(2026, 3, 1), next_run_date: Time.utc(2026, 4, 1))

    assert_equal 'ended_by_count', task.end_reason
  end

  # ---- checker ----

  def test_checker_disables_task_when_next_run_would_be_after_end_date
    task = create_task(interval_number: 1, interval_units: 'day', next_run_date: 1.hour.ago,
                       end_date: 2.hours.from_now)

    assert_difference('Issue.count') { ScheduledTasksChecker.checktasks! }

    task.reload
    assert_not task.is_active?
    assert task.next_run_date > task.end_date
    assert_equal 1, task.occurrences_count
    assert_nil task.last_error
    assert_equal ['ended_by_date'], journal_actions(task)
  end

  def test_checker_keeps_task_active_while_next_run_is_not_after_end_date
    task = create_task(interval_number: 1, interval_units: 'day', next_run_date: 1.hour.ago,
                       end_date: 3.days.from_now)

    ScheduledTasksChecker.checktasks!

    task.reload
    assert task.is_active?
    assert task.next_run_date > Time.current
    assert_empty journal_actions(task)
  end

  def test_checker_keeps_task_active_when_next_run_equals_end_date
    anchor = 1.hour.ago.change(usec: 0)
    task = create_task(interval_number: 1, interval_units: 'day', next_run_date: anchor, end_date: anchor + 1.day)

    ScheduledTasksChecker.checktasks!

    task.reload
    assert_equal task.end_date, task.next_run_date
    assert task.is_active?
  end

  def test_checker_disables_task_when_max_occurrences_reached
    task = create_task(interval_number: 1, interval_units: 'day', next_run_date: 1.hour.ago, max_occurrences: 2)

    assert_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    assert task.reload.is_active?
    assert_equal 1, task.occurrences_count

    task.update!(next_run_date: 1.hour.ago)
    assert_difference('Issue.count') { ScheduledTasksChecker.checktasks! }

    task.reload
    assert_not task.is_active?
    assert_equal 2, task.occurrences_count
    assert_equal ['ended_by_count'], journal_actions(task)

    task.update!(next_run_date: 1.hour.ago)
    assert_no_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
  end

  def test_checker_does_not_count_an_occurrence_skipped_because_the_previous_issue_is_open
    task = create_task(interval_number: 1, interval_units: 'day', next_run_date: 1.hour.ago,
                       max_occurrences: 2, if_previous_open: 'skip')

    assert_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    assert_equal 1, task.reload.occurrences_count

    task.update!(next_run_date: 1.hour.ago)
    assert_no_difference('Issue.count') { ScheduledTasksChecker.checktasks! }

    task.reload
    assert task.is_active?
    assert_equal 1, task.occurrences_count
    assert task.last_skipped_issue_id.present?
    assert_equal [], journal_actions(task)
  end

  def test_checker_ends_task_with_a_single_occurrence_after_its_only_run
    task = create_task(interval_number: 1, interval_units: 'month', next_run_date: 1.hour.ago, max_occurrences: 1)

    assert_difference('Issue.count') { ScheduledTasksChecker.checktasks! }

    task.reload
    assert_not task.is_active?
    assert_equal 1, task.occurrences_count
  end

  def test_checker_ends_task_by_whichever_condition_comes_first
    by_date = create_task(subject: 'By date', interval_number: 1, interval_units: 'day', next_run_date: 1.hour.ago,
                          end_date: 2.hours.from_now, max_occurrences: 10)
    by_count = create_task(subject: 'By count', interval_number: 1, interval_units: 'day', next_run_date: 1.hour.ago,
                           end_date: 1.year.from_now, max_occurrences: 1)

    ScheduledTasksChecker.checktasks!

    assert_equal ['ended_by_date'], journal_actions(by_date.reload)
    assert_equal ['ended_by_count'], journal_actions(by_count.reload)
    assert_not by_date.is_active?
    assert_not by_count.is_active?
  end

  def test_checker_ends_task_without_running_when_max_was_lowered_below_past_runs
    task = create_task(interval_number: 1, interval_units: 'day', next_run_date: 1.hour.ago, max_occurrences: 5)
    task.update_columns(occurrences_count: 5, max_occurrences: 3)

    assert_no_difference('Issue.count') { ScheduledTasksChecker.checktasks! }

    task.reload
    assert_not task.is_active?
    assert_equal ['ended_by_count'], journal_actions(task)
  end

  def test_checker_counts_a_run_whose_issue_was_created_even_if_subtasks_failed
    task = create_task(interval_number: 1, interval_units: 'day', next_run_date: 1.hour.ago, max_occurrences: 1,
                       subtasks: [{ 'subject' => 'Child', 'tracker_id' => '999' }])

    ScheduledTasksChecker.checktasks!

    task.reload
    assert_equal 1, task.occurrences_count
    assert_not task.is_active?
    assert_match(/Child/, task.last_error)
  end

  def test_checker_does_not_count_a_run_whose_issue_failed_to_save
    task = create_task(interval_number: 1, interval_units: 'day', next_run_date: 1.hour.ago, max_occurrences: 1)
    Issue.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid.new(Issue.new))

    assert_no_difference('Issue.count') { ScheduledTasksChecker.checktasks! }

    task.reload
    assert_equal 0, task.occurrences_count
    assert task.is_active?
    assert task.next_run_date > Time.current
  end

  def test_end_journal_entry_is_attributed_to_the_task_author
    task = create_task(author_id: 2, interval_number: 1, interval_units: 'day', next_run_date: 1.hour.ago,
                       max_occurrences: 1)

    ScheduledTasksChecker.checktasks!

    journal = PeriodictaskJournal.where(periodictask_id: task.id, action: 'ended_by_count').first
    assert_equal 2, journal.user_id
    assert_equal @project.id, journal.project_id
    assert_equal "#{I18n.t(:label_periodictask_journal_ended_by_count)}: End condition", journal.event_title
    assert_equal 'periodictask-ended_by_count', journal.event_type
  end

  def test_journal_accepts_end_actions
    %w[ended_by_date ended_by_count].each do |action|
      assert_includes PeriodictaskJournal::ACTIONS, action
    end
  end

  # ---- copy ----

  def test_copy_from_takes_the_end_condition_but_resets_the_occurrence_count
    source = create_task(end_date: 1.year.from_now, max_occurrences: 5)
    source.update_columns(occurrences_count: 3)

    copy = Periodictask.new(project: @project, author_id: 3).copy_from(source)

    assert_equal source.end_date.to_i, copy.end_date.to_i
    assert_equal 5, copy.max_occurrences
    assert_equal 0, copy.occurrences_count
  end

  private

  def build_task(attrs = {})
    Periodictask.new({
      project: @project, tracker_id: 1, assigned_to_id: 2, author_id: 1,
      subject: 'End condition', interval_number: 1, interval_units: 'month'
    }.merge(attrs))
  end

  def create_task(attrs = {})
    build_task(attrs).tap(&:save!)
  end

  def journal_actions(task)
    PeriodictaskJournal.where(periodictask_id: task.id).order(:id).pluck(:action)
  end
end
