active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class AddTimestampsToPeriodictasks < active_record_migration_class
  def self.up
    add_column :periodictasks, :created_at, :datetime
    add_column :periodictasks, :updated_at, :datetime

    # Backfill legacy rows that predate these columns so the detail page can
    # show an "added ... ago" line for them.
    now = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
    execute("UPDATE periodictasks SET created_at = '#{now}', updated_at = '#{now}' WHERE created_at IS NULL")
  end

  def self.down
    remove_column :periodictasks, :created_at
    remove_column :periodictasks, :updated_at
  end
end
