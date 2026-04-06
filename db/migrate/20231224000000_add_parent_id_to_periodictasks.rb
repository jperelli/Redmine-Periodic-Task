active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class AddParentIdToPeriodictasks < active_record_migration_class
  def self.up
    add_column :periodictasks, :parent_id, :integer, :null => true, :default => nil
  end

  def self.down
    remove_column :periodictasks, :parent_id
  end
end
