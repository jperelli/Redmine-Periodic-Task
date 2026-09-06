active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class AddWeekendAdjustmentToPeriodictasks < active_record_migration_class
  def self.up
    add_column :periodictasks, :weekend_adjustment, :string, :limit => 30, :null => false, :default => 'none'
  end

  def self.down
    remove_column :periodictasks, :weekend_adjustment
  end
end
