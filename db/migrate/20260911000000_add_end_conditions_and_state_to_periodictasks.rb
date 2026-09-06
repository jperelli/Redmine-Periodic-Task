active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

# End condition (end_date / max_occurrences / occurrences_count) and the
# three-way state (active / inactive / ended) that replaces the is_active flag.
class AddEndConditionsAndStateToPeriodictasks < active_record_migration_class
  def self.up
    add_column :periodictasks, :end_date, :datetime, :null => true, :default => nil
    add_column :periodictasks, :max_occurrences, :integer, :null => true, :default => nil
    add_column :periodictasks, :occurrences_count, :integer, :null => false, :default => 0

    add_column :periodictasks, :state, :string, :limit => 10, :null => false, :default => 'active'
    add_column :periodictasks, :ended_at, :datetime, :null => true, :default => nil
    execute "UPDATE periodictasks SET state = 'inactive' WHERE is_active = #{quoted_false}"
    remove_index :periodictasks, [:is_active, :next_run_date]
    remove_column :periodictasks, :is_active
    add_index :periodictasks, [:state, :next_run_date]
  end

  def self.down
    add_column :periodictasks, :is_active, :boolean, :null => false, :default => true
    execute "UPDATE periodictasks SET is_active = #{quoted_false} WHERE state <> 'active'"
    remove_index :periodictasks, [:state, :next_run_date]
    remove_column :periodictasks, :ended_at
    remove_column :periodictasks, :state
    add_index :periodictasks, [:is_active, :next_run_date]

    remove_column :periodictasks, :end_date
    remove_column :periodictasks, :max_occurrences
    remove_column :periodictasks, :occurrences_count
  end
end
