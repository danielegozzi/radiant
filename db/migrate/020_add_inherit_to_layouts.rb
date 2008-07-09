class AddInheritToLayouts < ActiveRecord::Migration
  def self.up
    add_column :layouts, :inherit_layout_id, :integer
  end

  def self.down
    remove_column :layouts, :inherit_layout_id
  end
end
