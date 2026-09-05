# Single-row table used to elect one process to run the scheduler when it is
# triggered from web requests (several Puma/Passenger workers, or several
# servers, all see the same requests).
class PeriodictaskSchedulerLock < ActiveRecord::Base
  ROW_ID = 1

  # Atomically claims the lock if the last run is older than +interval+.
  # Returns true for exactly one caller per interval, across all processes.
  def self.claim?(interval, now = Time.current)
    ensure_row!
    updated = where(id: ROW_ID)
              .where('last_run_at IS NULL OR last_run_at <= ?', now - interval)
              .update_all(last_run_at: now)
    updated == 1
  end

  def self.last_run_at
    where(id: ROW_ID).pick(:last_run_at)
  end

  def self.ensure_row!
    return if exists?(id: ROW_ID)

    create!(id: ROW_ID)
  rescue ActiveRecord::RecordNotUnique
    # another process inserted it first
  end
end
