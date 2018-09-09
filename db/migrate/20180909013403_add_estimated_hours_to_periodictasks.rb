class AddEstimatedHoursToPeriodictasks < ActiveRecord::Migration
  def self.up
    add_column :periodictasks, :estimated_hours, :float, :null => true, :default => nil
  end

  def self.down
    remove_column :periodictasks, :estimated_hours
  end
end
