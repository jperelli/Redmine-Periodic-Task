class CreatePeriodictasks < ActiveRecord::Migration
  def self.up
    create_table :periodictasks do |t|
      t.column :project_id, :integer
      t.column :tracker_id, :integer
      t.column :assigned_to_id, :integer
      t.column :author_id, :integer
      t.column :subject, :string
      t.column :interval_number, :integer
      t.column :interval_units, :string
      t.column :last_assigned_date, :datetime
      t.column :next_run_date, :datetime
    end
  end

  def self.down
    drop_table :periodictasks
  end
end
