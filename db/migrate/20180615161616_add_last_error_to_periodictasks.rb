class AddLastErrorToPeriodictasks < ActiveRecord::Migration
  def self.up
    add_column :periodictasks, :last_error, :string
  end

  def self.down
    remove_column :periodictasks, :last_error
  end
end
