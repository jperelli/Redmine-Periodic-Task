# Audit entry for a create/update/delete of a Periodictask, recorded so the
# action shows up in Redmine's activity log (both the project Activity tab and
# the per-user /activity page). This mirrors how Journal records issue history.
class PeriodictaskJournal < ApplicationRecord
  include Redmine::I18n

  belongs_to :project
  belongs_to :user
  belongs_to :periodictask, optional: true

  ACTIONS = %w[create update delete run].freeze
  validates :action, inclusion: { in: ACTIONS }

  acts_as_event(
    datetime: :created_on,
    title: proc { |o| o.event_title },
    description: '',
    author: :user,
    type: proc { |o| "periodictask-#{o.action}" },
    url: proc { |o| o.event_url_hash },
    group: :periodictask
  )

  acts_as_activity_provider(
    type: 'periodictasks',
    permission: :periodictask,
    author_key: :user_id,
    timestamp: "#{table_name}.created_on",
    scope: proc { joins(:project).preload(:user, :periodictask) }
  )

  def event_title
    "#{l("label_periodictask_journal_#{action}")}: #{subject}"
  end

  # Deleted tasks (and any orphaned entry) link back to the task list; existing
  # tasks link to their detail page.
  def event_url_hash
    if action == 'delete' || periodictask_id.nil?
      { controller: 'periodictask', action: 'index', project_id: project.identifier }
    else
      { controller: 'periodictask', action: 'show', id: periodictask_id, project_id: project.identifier }
    end
  end
end
