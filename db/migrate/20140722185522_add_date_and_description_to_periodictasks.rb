active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class AddDateAndDescriptionToPeriodictasks < active_record_migration_class
  def self.up
    add_column :periodictasks, :set_start_date, :boolean, :null => false, :default => false
    add_column :periodictasks, :due_date_number, :integer, :null => true, :default => nil
    add_column :periodictasks, :due_date_units, :string, :null => true
    add_column :periodictasks, :description, :text, :null => true
  end

  def self.down
    remove_column :periodictasks, :set_start_date
    remove_column :periodictasks, :due_date_number
    remove_column :periodictasks, :due_date_units
    remove_column :periodictasks, :description
  end
end
