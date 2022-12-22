# frozen_string_literal: true

require 'test_helper'
require 'temping'

class HierarchySiblingsOfTest < Minitest::Test
  def setup
    create_siblings_of_test_hierarchy_parents_table
    create_siblings_of_test_items_table
    create_siblings_of_decoy_items_table

    @hierarchy_parent = SiblingsOfTestHierarchyParent.create!(name: 'parent')
    @object = @hierarchy_parent.siblings_of_test_items.create(name: 'obj')
  end

  def teardown
    Temping.teardown
  end

  def test_should_return_self_and_siblings
    sib1 = @hierarchy_parent.siblings_of_test_items.create(name: 'sib1')
    sib2 = @hierarchy_parent.siblings_of_test_items.create(name: 'sib2')

    sibling_ids = SiblingsOfTestItem.hierarchy_siblings_of(@object).pluck(:id)

    assert_equal [@object.id, sib1.id, sib2.id].sort, sibling_ids.sort
  end

  def test_should_not_return_other_children
    hierarchy_parent2 = SiblingsOfTestHierarchyParent.create(name: 'parent2')
    hierarchy_parent2.siblings_of_test_items.create(name: 'obj2')

    assert_equal [@object.id],
                 SiblingsOfTestItem.hierarchy_siblings_of(@object).pluck(:id)
  end

  def test_should_not_return_other_object_types
    decoy = @hierarchy_parent.siblings_of_decoy_items.create(name: 'DECOY')

    # Decoy shows up as a hierarchy_parent item
    assert_equal [decoy.id],
                 @hierarchy_parent.siblings_of_decoy_items.pluck(:id)

    # But it doesn't show up as a sibling to @object
    sibling_ids = SiblingsOfTestItem.hierarchy_siblings_of(@object).pluck(:id)

    assert_equal [@object.id].sort, sibling_ids
  end

  private

  def create_siblings_of_test_hierarchy_parents_table
    Temping.create :siblings_of_test_hierarchy_parents do
      include Hierarchable
      hierarchable

      has_many :siblings_of_test_items
      has_many :siblings_of_decoy_items

      with_columns do |t|
        t.string :name, null: false
        t.references :hierarchy_root,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_sibs_of_test_parents_on_hierarchy_root'
                     }
        t.references :hierarchy_parent,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_sibs_of_test_parents_on_hierarchy_parent'
                     }
        t.string :hierarchy_ancestors_path,
                 index: { name: 'idx_sibs_of_test_parents_on_hierarchy_path' }
        t.integer :version_id
        t.timestamps index: true
      end
    end
  end

  def create_siblings_of_test_items_table
    Temping.create :siblings_of_test_items do
      include Hierarchable
      hierarchable parent_source: :siblings_of_test_hierarchy_parent

      belongs_to :siblings_of_test_hierarchy_parent

      with_columns do |t|
        t.integer :siblings_of_test_hierarchy_parent_id
        t.string :name, null: false
        t.references :hierarchy_root,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_sibs_of_test_items_on_hierarchy_root'
                     }
        t.references :hierarchy_parent,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_sibs_of_test_items_on_hierarchy_parent'
                     }
        t.string :hierarchy_ancestors_path,
                 index: {
                   name: 'idx_sibs_of_test_items_on_hierarchy_path'
                 }
        t.timestamps index: true
      end
    end
  end

  def create_siblings_of_decoy_items_table
    Temping.create :siblings_of_decoy_items do
      include Hierarchable
      hierarchable parent_source: :siblings_of_test_hierarchy_parent

      belongs_to :siblings_of_test_hierarchy_parent

      with_columns do |t|
        t.integer :siblings_of_test_hierarchy_parent_id
        t.string :name, null: false
        t.references :hierarchy_root,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_sibs_of_test_decoy_items_on_hierarchy_root'
                     }
        t.references :hierarchy_parent,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_sibs_of_test_decoy_items_on_hierarchy_parent'
                     }
        t.string :hierarchy_ancestors_path,
                 index: {
                   name: 'idx_sibs_of_test_decory_items_on_hierarchy_path'
                 }
        t.timestamps index: true
      end
    end
  end
end
