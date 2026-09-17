# A recurring item read from an uploaded file, waiting for an administrator
# to choose the project it becomes a periodic task in. Rows stay staged
# until they are imported or discarded, so a file can be triaged over
# several sessions. Once the task is created the row is gone.
class PeriodictaskImport < (defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base)
  include Redmine::I18n

  SOURCES = [RedminePeriodictask::IcalImport::SOURCE, RedminePeriodictask::JscalImport::SOURCE].freeze

  belongs_to :project, optional: true
  belongs_to :user, optional: true

  attribute :task_attributes, :json, default: -> { {} }
  attribute :warnings, :json, default: -> { [] }

  validates :source, inclusion: { in: SOURCES }
  validates :subject, presence: true

  before_create { self.created_at ||= Time.current }

  scope :sorted, -> { order(:id) }

  # Projects a staged item can be imported into: active ones with the
  # periodic tasks module enabled, so the task is visible once created.
  def self.target_projects
    Project.active.has_module(:periodictask).sorted
  end

  def self.target_project?(project)
    project.present? && project.active? && project.module_enabled?(:periodictask)
  end

  # Stages the items parsed from a file. An item whose UID is already staged
  # (from any file, in any format: a calendar exported twice as .ics and as
  # JSCalendar keeps its UIDs) is not added again, so re-uploading the same
  # calendar is harmless. Returns the number of rows added.
  def self.stage(items, source:, user:)
    staged_uids = where.not(uid: nil).pluck(:uid).to_set
    items.count do |item|
      next false if item.uid.present? && staged_uids.include?(item.uid)

      create!(source: source, uid: item.uid, subject: item.subject, description: item.description,
              rule: item.rule, task_attributes: item.attributes, warnings: item.warnings, user: user)
      staged_uids << item.uid if item.uid.present?
      true
    end
  end

  # The task as it would be created in +project+, unsaved: for the triage
  # table and for import. The tracker is the project's first one, like the
  # form's default.
  def build_periodictask(project = nil, author = nil)
    task = Periodictask.new(project: project, author_id: author&.id, subject: subject, description: description)
    task.attributes = task_attributes.to_h.slice(*Periodictask::IMPORT_ATTRIBUTES)
    task.tracker_id = project.trackers.first&.id if project
    task
  end

  # Creates the periodic task in +project+ as +user+ and removes the staged
  # row. A first run in the past (the calendar item started long ago) moves
  # to the next occurrence of its schedule, keeping the anchor's cadence and
  # time of day. On failure the row stays, with the chosen project and the
  # reason, so the administrator can see why. Returns the task when created.
  def import(project, user = User.current, now = Time.current)
    task = build_periodictask(project, user)
    unless self.class.target_project?(project)
      return record_failure(project, l(:error_periodictask_import_project_not_allowed))
    end

    task.next_run_date = task.get_next_run_date(now) if task.next_run_date.nil? || task.next_run_date <= now
    issue = task.generate_issue(now)
    errors = if issue.nil?
               [l(:label_project_missing_or_closed)]
             elsif !issue.valid?
               issue.errors.full_messages
             elsif !task.save
               task.errors.full_messages
             else
               []
             end
    return record_failure(project, errors.join(', ')) if errors.any?

    task.log_activity('create', user)
    destroy
    task
  end

  private

  def record_failure(project, message)
    update_columns(project_id: project&.id, last_error: message)
    nil
  end
end
