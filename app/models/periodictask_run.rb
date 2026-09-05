# One row per execution of ScheduledTasksChecker, shown on the plugin
# settings page so admins can verify that their cron / web / external
# scheduler is actually firing and see any errors.
#
# Consecutive runs that found nothing to do (and came from the same source)
# are coalesced into a single row (+runs_count+ / +last_run_at+), so the
# capped history covers days of real activity instead of a few hours of
# "0 tasks due" from the web scheduler.
class PeriodictaskRun < ActiveRecord::Base
  KEEP = 50
  SOURCES = %w[rake web endpoint manual].freeze

  validates :source, inclusion: { in: SOURCES }

  scope :recent, -> { order(started_at: :desc, id: :desc) }

  def self.record!(source:, started_at:, finished_at:, tasks_due:, issues_created:, errors:)
    attrs = { source: source, started_at: started_at, last_run_at: started_at,
              duration_ms: ((finished_at - started_at) * 1000).round,
              tasks_due: tasks_due, issues_created: issues_created,
              error_messages: errors.reject(&:blank?).join("\n").presence }

    run = coalesce_target(attrs) || create!(attrs)
    prune!
    run
  end

  def self.prune!
    keep_ids = recent.limit(KEEP).pluck(:id)
    where.not(id: keep_ids).delete_all
  end

  def noop?
    tasks_due.zero? && error_messages.blank?
  end

  def self.coalesce_target(attrs)
    return nil unless attrs[:tasks_due].zero? && attrs[:error_messages].nil?

    last = recent.first
    return nil unless last&.noop? && last.source == attrs[:source]

    last.update!(runs_count: last.runs_count + 1, last_run_at: attrs[:last_run_at],
                 duration_ms: attrs[:duration_ms])
    last
  end
  private_class_method :coalesce_target
end
