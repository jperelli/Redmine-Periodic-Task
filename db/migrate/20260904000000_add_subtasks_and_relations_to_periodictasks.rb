active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class AddSubtasksAndRelationsToPeriodictasks < active_record_migration_class
  def self.up
    add_column :periodictasks, :subtasks, :json
    add_column :periodictasks, :relations, :json
  end

  def self.down
    remove_column :periodictasks, :subtasks
    remove_column :periodictasks, :relations
  end
end
