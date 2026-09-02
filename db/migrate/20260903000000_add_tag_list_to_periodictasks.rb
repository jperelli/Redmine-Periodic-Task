active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class AddTagListToPeriodictasks < active_record_migration_class
  def self.up
    add_column :periodictasks, :tag_list, :string, :null => true, :default => nil
  end

  def self.down
    remove_column :periodictasks, :tag_list
  end
end
