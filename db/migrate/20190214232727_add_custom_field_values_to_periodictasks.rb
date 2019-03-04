active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class AddCustomFieldValuesToPeriodictasks < active_record_migration_class
  def self.up
    add_column :periodictasks, :custom_field_values, :text
  end

  def self.down
    remove_column :periodictasks, :custom_field_values
  end
end
