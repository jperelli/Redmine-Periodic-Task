active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class AddWatcherUserIdsToPeriodictasks < active_record_migration_class
  def self.up
    add_column :periodictasks, :watcher_user_ids, :json
  end

  def self.down
    remove_column :periodictasks, :watcher_user_ids
  end
end
