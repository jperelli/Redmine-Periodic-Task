active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class AddAssigneeRotationToPeriodictasks < active_record_migration_class
  def self.up
    add_column :periodictasks, :rotation_ids, :json
    add_column :periodictasks, :rotation_index, :integer, :null => false, :default => 0
  end

  def self.down
    remove_column :periodictasks, :rotation_ids
    remove_column :periodictasks, :rotation_index
  end
end
