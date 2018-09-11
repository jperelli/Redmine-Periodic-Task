class AddChecklistsTemplateIdToPeriodictasks < ActiveRecord::Migration
  def self.up
    add_column :periodictasks, :checklists_template_id, :integer, :null => true, :default => nil
  end

  def self.down
    remove_column :periodictasks, :checklists_template_id
  end
end
