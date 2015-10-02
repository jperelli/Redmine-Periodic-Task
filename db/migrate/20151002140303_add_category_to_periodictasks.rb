class AddCategoryToPeriodictasks < ActiveRecord::Migration
  def self.up
    add_column :periodictasks, :issue_category_id, :integer, :null => true, :default => nil
  end

  def self.down
    remove_column :periodictasks, :issue_category_id
  end
end
