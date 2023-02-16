active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class AddIsDisabledToPeriodictasks < active_record_migration_class
  def self.up
    add_column :periodictasks, :is_disabled, :boolean, :null => false, :default => false
  end

  def self.down
    remove_column :periodictasks, :is_disabled
  end
end
