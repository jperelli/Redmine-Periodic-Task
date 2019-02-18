active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class AddLastErrorToPeriodictasks < active_record_migration_class
  def self.up
    add_column :periodictasks, :last_error, :string
  end

  def self.down
    remove_column :periodictasks, :last_error
  end
end
