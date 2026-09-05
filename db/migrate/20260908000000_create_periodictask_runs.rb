active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class CreatePeriodictaskRuns < active_record_migration_class
  def self.up
    create_table :periodictask_runs do |t|
      t.datetime :started_at, null: false
      t.datetime :last_run_at, null: false
      t.integer :duration_ms, null: false, default: 0
      t.string :source, limit: 20, null: false
      t.integer :tasks_due, null: false, default: 0
      t.integer :issues_created, null: false, default: 0
      t.integer :runs_count, null: false, default: 1
      t.text :error_messages
    end
    add_index :periodictask_runs, :started_at
  end

  def self.down
    drop_table :periodictask_runs
  end
end
