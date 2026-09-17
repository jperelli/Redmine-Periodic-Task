active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

# Recurring items read from an uploaded file (iCalendar VTODO/VEVENT with an
# RRULE), staged until an administrator picks the project each one becomes a
# periodic task in.
class CreatePeriodictaskImports < active_record_migration_class
  def self.up
    create_table :periodictask_imports do |t|
      t.string :source, limit: 20, null: false
      t.string :uid
      t.string :subject, null: false
      t.text :description
      t.string :rule
      t.text :task_attributes
      t.text :warnings
      t.integer :project_id
      t.text :last_error
      t.integer :user_id
      t.datetime :created_at, null: false
    end
    add_index :periodictask_imports, :project_id
  end

  def self.down
    drop_table :periodictask_imports
  end
end
