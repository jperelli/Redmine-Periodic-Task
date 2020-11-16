active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class AddFacilityIdToPeriodictasks < active_record_migration_class
  def self.up
    add_column :periodictasks, :facility_id, :integer, :default => 0, :null => false, comment: 'Услуга'
  end

  def self.down
    remove_column :periodictasks, :facility_id
  end
end
