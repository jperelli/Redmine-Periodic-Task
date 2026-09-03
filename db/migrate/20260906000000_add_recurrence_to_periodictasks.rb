active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class AddRecurrenceToPeriodictasks < active_record_migration_class
  def self.up
    add_column :periodictasks, :weekdays, :json
    add_column :periodictasks, :monthly_mode, :string, :limit => 20, :null => true, :default => nil
    add_column :periodictasks, :month_weeks, :json
  end

  def self.down
    remove_column :periodictasks, :weekdays
    remove_column :periodictasks, :monthly_mode
    remove_column :periodictasks, :month_weeks
  end
end
