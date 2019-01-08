active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class AddCategoryToPeriodictasks < active_record_migration_class
  def self.up
    add_column :periodictasks, :issue_category_id, :integer, :null => true, :default => nil
  end

  def self.down
    remove_column :periodictasks, :issue_category_id
  end
end
