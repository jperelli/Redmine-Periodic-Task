require File.dirname(__FILE__) + '/../test_helper'

class PeriodictasksTest < ActiveSupport::TestCase
  plugin_fixtures :periodictasks

  fixtures :projects,
           :users,
           :roles,
           :members,
           :member_roles,
           :issues,
           :issue_statuses,
           :versions,
           :trackers,
           :projects_trackers,
           :issue_categories,
           :enabled_modules,
           :enumerations,
           :workflows,
           :custom_fields,
           :custom_values,
           :custom_fields_projects,
           :custom_fields_trackers,
           :watchers, :groups_users

  def test_create_one
    assert true
    User.current = User.find(1)
    task = Periodictask.find(1)
    issue = task.generate_issue(Time.now)
    assert_equal 'subject ' + Time.now.strftime('%m %B'), issue.subject
    assert_equal 'description ' + Time.now.strftime('%m %B'), issue.description
    assert_equal 4, issue.estimated_hours
    assert_equal (Time.now + 3.days).strftime('%Y-%m-%d'), issue.due_date.strftime('%Y-%m-%d')
  end

  def test_create_two
    assert true
    User.current = User.find(1)
    task = Periodictask.find(2)
    issue = task.generate_issue(Time.now)
    assert_equal 'subject2 ' + Time.now.strftime('%m %B'), issue.subject
    assert_equal 'description2 ' + Time.now.strftime('%m %B'), issue.description
    assert_equal 4, issue.estimated_hours
    assert_equal (Time.now+1.month).strftime('%Y-%m-%d'), issue.due_date.strftime('%Y-%m-%d')
  end

  def test_create_with_business_days
    assert true
    User.current = User.find(1)
    task = Periodictask.find(3)
    issue = task.generate_issue(Time.now)
    assert_equal 'subject2 ' + Time.now.strftime('%m %B'), issue.subject
    assert_equal 'description2 ' + Time.now.strftime('%m %B'), issue.description
    assert_equal 5, issue.estimated_hours
    assert_equal 21.business_day.from_now.strftime('%Y-%m-%d'), issue.due_date.strftime('%Y-%m-%d')
  end
end
