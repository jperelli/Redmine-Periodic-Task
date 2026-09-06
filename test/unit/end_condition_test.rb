require "#{File.dirname(__FILE__)}/../test_helper"

# End condition of a periodic task: an optional end date and/or a maximum
# number of scheduled runs. Whichever is reached first ends the task (a
# derived state, independent of the user's Active flag) and the reason is
# written to the activity log.
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

  def test_end_date_is_only_checked_when_one_of_the_dates_is_being_changed
    anchor = Time.utc(2026, 3, 1, 10, 0, 0)
    task = create_task(next_run_date: anchor, end_date: anchor + 1.day)
    task.update_columns(next_run_date: anchor + 2.days)
    task.reload

    assert task.ended?
    task.subject = 'Renamed'
    assert task.valid?
    task.is_active = false
    assert task.valid?

    task.end_date = anchor + 1.day + 1.hour
    assert_not task.valid?
    assert_includes task.errors.full_messages, I18n.t(:error_end_date_before_next_run)

    task.end_date = anchor + 2.days
    assert task.valid?
    assert_not task.ended?
  end

  def test_moving_the_next_run_past_the_end_date_is_rejected
    anchor = Time.utc(2026, 3, 1, 10, 0, 0)
    task = create_task(next_run_date: anchor, end_date: anchor + 1.day)

    task.next_run_date = anchor + 1.day
    assert task.valid?

    task.next_run_date = anchor + 1.day + 1.second
    assert_not task.valid?
    assert_includes task.errors.full_messages, I18n.t(:error_end_date_before_next_run)
  end

  def test_scheduler_can_store_the_next_run_past_the_end_date
    anchor = Time.utc(2026, 3, 1, 10, 0, 0)
    task = create_task(next_run_date: anchor, end_date: anchor + 1.day)

    task.next_run_date = anchor + 2.days
    task.save_run!

    assert task.reload.ended?
    assert_equal anchor + 2.days, task.next_run_date
  end

  def test_max_occurrences_must_be_a_positive_integer_or_blank
    [nil, 1, '1', 10, '10'].each do |n|
      assert build_task(max_occurrences: n).valid?, "#{n.inspect} should be valid"
    end
    assert_nil build_task(max_occurrences: '').max_occurrences
    assert build_task(max_occurrences: '').valid?

    [0, -1, '0', '-1', 1.9, '1.9', 0.5, '0.5', 'ten'].each do |n|
      task = build_task(max_occurrences: n)
      assert_not task.valid?, "#{n.inspect} should be invalid"
      assert task.errors[:max_occurrences].any?, "#{n.inspect} should fail on max_occurrences"
    end
  end

  def test_fractional_max_occurrences_is_rejected_rather_than_truncated
    task = create_task(max_occurrences: 2)

    assert_not task.update(max_occurrences: 1.9)
    assert_not task.update(max_occurrences: '1.9')
    assert_equal 2, task.reload.max_occurrences
  end

  # ---- end_reason ----

  def test_end_reason_is_nil_without_end_condition
    assert_nil build_task(next_run_date: 1.day.ago).end_reason
    assert_not build_task(next_run_date: 1.day.ago).ended?
  end

  def test_end_reason_by_date_only_when_next_run_is_strictly_after_end_date
    end_date = Time.utc(2026, 3, 1, 10, 0, 0)
    task = build_task(end_date: end_date)

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
    task = build_task(max_occurrences: 1, occurrences_count: 1,
                      end_date: Time.utc(2026, 3, 1), next_run_date: Time.utc(2026, 4, 1))

    assert_equal 'ended_by_count', task.end_reason
  end

  def test_ended_is_independent_of_the_active_flag
    task = build_task(max_occurrences: 1, occurrences_count: 1, is_active: false)

    assert task.ended?
    assert_not task.is_active?
    assert_not task.runnable?

    task.is_active = true
    assert task.ended?
    assert_not task.runnable?

    task.max_occurrences = 2
    assert_not task.ended?
    assert task.runnable?
  end

  def test_runnable_scope_matches_the_ruby_predicates
    anchor = Time.utc(2026, 3, 1, 10, 0, 0)
    forever = create_task(subject: 'Forever', next_run_date: anchor)
    paused = create_task(subject: 'Paused', next_run_date: anchor, is_active: false)
    last_run_pending = create_task(subject: 'Last run pending', next_run_date: anchor, end_date: anchor)
    by_date = create_task(subject: 'By date', next_run_date: anchor, end_date: anchor + 1.day)
    by_date.update_columns(next_run_date: anchor + 2.days)
    by_count = create_task(subject: 'By count', next_run_date: anchor, max_occurrences: 2)
    by_count.update_columns(occurrences_count: 2)
    one_left = create_task(subject: 'One left', next_run_date: anchor, max_occurrences: 2)
    one_left.update_columns(occurrences_count: 1)

    tasks = [forever, paused, last_run_pending, by_date, by_count, one_left].each(&:reload)
    assert_equal [forever, last_run_pending, one_left].map(&:id).sort,
                 Periodictask.runnable.where(id: tasks.map(&:id)).pluck(:id).sort
    assert_equal tasks.select(&:runnable?).map(&:id).sort,
                 Periodictask.runnable.where(id: tasks.map(&:id)).pluck(:id).sort
    assert_equal tasks.reject(&:ended?).map(&:id).sort,
                 Periodictask.not_ended.where(id: tasks.map(&:id)).pluck(:id).sort
  end

  # ---- checker ----

  def test_checker_ends_task_when_next_run_would_be_after_end_date
    task = create_task(interval_number: 1, interval_units: 'day', next_run_date: 1.hour.ago,
                       end_date: 2.hours.from_now)

    assert_difference('Issue.count') { ScheduledTasksChecker.checktasks! }

    task.reload
    assert task.ended?
    assert task.is_active?
    assert_not task.runnable?
    assert task.next_run_date > task.end_date
    assert_equal 1, task.occurrences_count
    assert_nil task.last_error
    assert_equal ['ended_by_date'], journal_actions(task)
  end

  def test_ended_task_resumes_once_its_end_condition_is_changed
    task = create_task(interval_number: 1, interval_units: 'day', next_run_date: 1.hour.ago, max_occurrences: 1)
    ScheduledTasksChecker.checktasks!
    assert task.reload.ended?

    task.update!(next_run_date: 1.hour.ago)
    assert_no_difference('Issue.count') { ScheduledTasksChecker.checktasks! }

    task.update!(max_occurrences: 2)
    assert_not task.ended?
    assert task.runnable?

    assert_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    task.reload
    assert task.ended?
    assert_equal 2, task.occurrences_count
    assert_equal %w[ended_by_count ended_by_count], journal_actions(task)
  end

  def test_checker_keeps_task_active_while_next_run_is_not_after_end_date
    task = create_task(interval_number: 1, interval_units: 'day', next_run_date: 1.hour.ago,
                       end_date: 3.days.from_now)

    ScheduledTasksChecker.checktasks!

    task.reload
    assert task.runnable?
    assert task.next_run_date > Time.current
    assert_empty journal_actions(task)
  end

  def test_checker_keeps_task_active_when_next_run_equals_end_date
    anchor = 1.hour.ago.change(usec: 0)
    task = create_task(interval_number: 1, interval_units: 'day', next_run_date: anchor, end_date: anchor + 1.day)

    ScheduledTasksChecker.checktasks!

    task.reload
    assert_equal task.end_date, task.next_run_date
    assert task.runnable?
  end

  def test_checker_ends_task_when_max_occurrences_reached
    task = create_task(interval_number: 1, interval_units: 'day', next_run_date: 1.hour.ago, max_occurrences: 2)

    assert_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    assert task.reload.runnable?
    assert_equal 1, task.occurrences_count

    task.update!(next_run_date: 1.hour.ago)
    assert_difference('Issue.count') { ScheduledTasksChecker.checktasks! }

    task.reload
    assert task.ended?
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
    assert task.runnable?
    assert_equal 1, task.occurrences_count
    assert task.last_skipped_issue_id.present?
    assert_equal [], journal_actions(task)
  end

  def test_checker_ends_task_with_a_single_occurrence_after_its_only_run
    task = create_task(interval_number: 1, interval_units: 'month', next_run_date: 1.hour.ago, max_occurrences: 1)

    assert_difference('Issue.count') { ScheduledTasksChecker.checktasks! }

    task.reload
    assert task.ended?
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
    assert by_date.ended?
    assert by_count.ended?
  end

  def test_task_whose_max_was_lowered_below_past_runs_is_ended_at_once_and_not_run
    task = create_task(interval_number: 1, interval_units: 'day', next_run_date: 1.hour.ago, max_occurrences: 5)
    task.update_columns(occurrences_count: 5)
    task.reload.update!(max_occurrences: 3)

    assert task.ended?
    assert_no_difference('Issue.count') { ScheduledTasksChecker.checktasks! }
    assert_equal 5, task.reload.occurrences_count
    assert_empty journal_actions(task)
  end

  def test_inactive_task_is_not_ended_by_an_end_date_that_passed_while_it_was_paused
    task = create_task(interval_number: 1, interval_units: 'day', next_run_date: 2.days.ago,
                       end_date: 1.day.ago, is_active: false)

    assert_not task.ended?
    assert_no_difference('Issue.count') { ScheduledTasksChecker.checktasks! }

    task.update!(is_active: true)
    assert_difference('Issue.count') { ScheduledTasksChecker.checktasks! }

    task.reload
    assert task.ended?
    assert_equal ['ended_by_date'], journal_actions(task)
  end

  def test_checker_counts_a_run_whose_issue_was_created_even_if_subtasks_failed
    task = create_task(interval_number: 1, interval_units: 'day', next_run_date: 1.hour.ago, max_occurrences: 1,
                       subtasks: [{ 'subject' => 'Child', 'tracker_id' => '999' }])

    ScheduledTasksChecker.checktasks!

    task.reload
    assert_equal 1, task.occurrences_count
    assert task.ended?
    assert_match(/Child/, task.last_error)
  end

  def test_checker_does_not_count_a_run_whose_issue_failed_to_save
    task = create_task(interval_number: 1, interval_units: 'day', next_run_date: 1.hour.ago, max_occurrences: 1)
    Issue.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid.new(Issue.new))

    assert_no_difference('Issue.count') { ScheduledTasksChecker.checktasks! }

    task.reload
    assert_equal 0, task.occurrences_count
    assert task.runnable?
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

  def test_copy_of_a_task_ended_by_count_is_not_ended_and_keeps_the_active_flag
    ended = create_task(max_occurrences: 1)
    ended.update_columns(occurrences_count: 1)
    assert ended.reload.ended?

    copy = Periodictask.new(project: @project, author_id: 3).copy_from(ended)
    assert_not copy.ended?
    assert copy.is_active?
    assert copy.valid?

    inactive = create_task(is_active: false)
    assert_not Periodictask.new(project: @project, author_id: 3).copy_from(inactive).is_active?
  end

  def test_copy_of_a_task_ended_by_date_needs_a_new_end_date
    anchor = Time.utc(2026, 3, 1, 10, 0, 0)
    ended = create_task(next_run_date: anchor, end_date: anchor)
    ended.update_columns(next_run_date: anchor + 1.month)

    copy = Periodictask.new(project: @project, author_id: 3).copy_from(ended.reload)
    assert_not copy.valid?
    assert_includes copy.errors.full_messages, I18n.t(:error_end_date_before_next_run)

    copy.end_date = anchor + 2.months
    assert copy.valid?
    assert_not copy.ended?
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
