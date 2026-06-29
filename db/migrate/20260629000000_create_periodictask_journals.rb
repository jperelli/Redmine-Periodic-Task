active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class CreatePeriodictaskJournals < active_record_migration_class
  def self.up
    create_table :periodictask_journals do |t|
      # The originating task. Kept nullable and without a foreign key so the
      # entry survives the task being deleted (delete events need it gone).
      t.integer :periodictask_id
      t.integer :project_id, null: false
      t.integer :user_id
      t.string  :action, null: false
      # Snapshot of the task subject so deleted tasks still render a title.
      t.string  :subject
      t.datetime :created_on
    end
    add_index :periodictask_journals, :periodictask_id
    add_index :periodictask_journals, %i[project_id created_on]
  end

  def self.down
    drop_table :periodictask_journals
  end
end
