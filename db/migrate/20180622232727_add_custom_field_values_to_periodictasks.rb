class AddCustomFieldValuesToPeriodictasks < ActiveRecord::Migration
  def self.up
    add_column :periodictasks, :custom_field_values, :text
  end

  def self.down
    remove_column :periodictasks, :custom_field_values
  end
end
