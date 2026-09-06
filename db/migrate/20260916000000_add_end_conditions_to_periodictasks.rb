active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

# End condition of a task: end_date and/or max_occurrences, with the number of
# scheduled runs made so far. Whether the task is ended is derived from them.
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
