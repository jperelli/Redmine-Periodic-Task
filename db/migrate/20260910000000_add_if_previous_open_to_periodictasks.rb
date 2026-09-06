active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class AddIfPreviousOpenToPeriodictasks < active_record_migration_class
  def self.up
    add_column :periodictasks, :if_previous_open, :string, :limit => 20, :null => false, :default => 'create'
    add_column :periodictasks, :last_skipped_issue_id, :integer, :null => true, :default => nil
    add_column :periodictasks, :last_skipped_at, :datetime, :null => true, :default => nil
    add_column :periodictask_runs, :notes, :text, :null => true, :default => nil
  end

  def self.down
    remove_column :periodictask_runs, :notes
    remove_column :periodictasks, :last_skipped_at
    remove_column :periodictasks, :last_skipped_issue_id
    remove_column :periodictasks, :if_previous_open
  end
end
