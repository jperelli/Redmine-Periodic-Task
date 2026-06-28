active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class CreatePeriodictaskIssues < active_record_migration_class
  def self.up
    create_table :periodictask_issues do |t|
      t.column :periodictask_id, :integer, null: false
      t.column :issue_id, :integer, null: false
      t.column :created_at, :datetime
    end
    add_index :periodictask_issues, :periodictask_id
    add_index :periodictask_issues, :issue_id
  end

  def self.down
    drop_table :periodictask_issues
  end
end
