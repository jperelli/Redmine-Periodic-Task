active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class AddActiveAndFixedVersionToPeriodictasks < active_record_migration_class
  def self.up
    add_column :periodictasks, :is_active, :boolean, :null => false, :default => true
    add_column :periodictasks, :fixed_version_id, :integer, :null => true, :default => nil
    add_index :periodictasks, [:is_active, :next_run_date]
  end

  def self.down
    remove_index :periodictasks, [:is_active, :next_run_date]
    remove_column :periodictasks, :is_active
    remove_column :periodictasks, :fixed_version_id
  end
end
