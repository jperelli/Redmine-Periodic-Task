active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class AddEndConditionsToPeriodictasks < active_record_migration_class
  def self.up
    add_column :periodictasks, :end_date, :datetime, :null => true, :default => nil
    add_column :periodictasks, :max_occurrences, :integer, :null => true, :default => nil
    add_column :periodictasks, :occurrences_count, :integer, :null => false, :default => 0
  end

  def self.down
    remove_column :periodictasks, :end_date
    remove_column :periodictasks, :max_occurrences
    remove_column :periodictasks, :occurrences_count
  end
end
