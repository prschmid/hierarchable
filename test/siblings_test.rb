# frozen_string_literal: true

require 'test_helper'
require 'temping'

class RecordSiblingsTest < Minitest::Test
  def setup
    create_siblings_test_hierarchy_parents_table
    create_siblings_test_items_table
    create_siblings_decoy_items_table

    @hierarchy_parent = SiblingsTestHierarchyParent.create!(name: 'parent')
    @object = @hierarchy_parent.siblings_test_items.create(name: 'obj')
  end

  def teardown
    Temping.teardown
  end

  def test_should_return_self_and_siblings
    sib1 = @hierarchy_parent.siblings_test_items.create(name: 'sib1')
    sib2 = @hierarchy_parent.siblings_test_items.create(name: 'sib2')

    sibling_ids = @object.siblings.pluck(:id)

    assert_equal [@object.id, sib1.id, sib2.id].sort, sibling_ids.sort
  end

  def test_can_exclude_self
    sib1 = @hierarchy_parent.siblings_test_items.create(name: 'sib1')
    sib2 = @hierarchy_parent.siblings_test_items.create(name: 'sib2')

    sibling_ids = @object.siblings(include_self: false).pluck(:id)

    assert_equal [sib1.id, sib2.id].sort, sibling_ids.sort
  end

  def test_should_not_return_other_children
    hierarchy_parent2 = SiblingsTestHierarchyParent.create(name: 'parent2')
    hierarchy_parent2.siblings_test_items.create(name: 'obj2')

    assert_equal [@object.id], @object.siblings.pluck(:id)
  end

  def test_should_not_return_other_object_types
    decoy = @hierarchy_parent.siblings_decoy_items.create(name: 'DECOY')

    # Decoy shows up as a hierarchy_parent item
    assert_equal [decoy.id],
                 @hierarchy_parent.siblings_decoy_items.pluck(:id)

    # But it doesn't show up as a sibling to @object
    sibling_ids = @object.siblings.pluck(:id)

    assert_equal [@object.id].sort, sibling_ids
  end

  private

  def create_siblings_test_hierarchy_parents_table
    Temping.create :siblings_test_hierarchy_parents do
      include Hierarchable
      hierarchable

      has_many :siblings_test_items
      has_many :siblings_decoy_items

      with_columns do |t|
        t.string :name, null: false
        t.references :hierarchy_root,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_sibs_test_parents_on_hierarchy_root'
                     }
        t.references :hierarchy_parent,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_sibs_test_parents_on_hierarchy_parent'
                     }
        t.string :hierarchy_ancestors_path,
                 index: { name: 'idx_sibs_test_parents_on_hierarchy_path' }
        t.timestamps index: true
      end
    end
  end

  def create_siblings_test_items_table
    Temping.create :siblings_test_items do
      include Hierarchable
      hierarchable parent_source: :siblings_test_hierarchy_parent

      belongs_to :siblings_test_hierarchy_parent

      with_columns do |t|
        t.integer :siblings_test_hierarchy_parent_id
        t.string :name, null: false
        t.references :hierarchy_root,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_sibs_test_test_items_on_hierarchy_root'
                     }
        t.references :hierarchy_parent,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_sibs_test_test_items_on_hierarchy_parent'
                     }
        t.string :hierarchy_ancestors_path,
                 index: { name: 'idx_sibs_test_test_items_on_hierarchy_path' }
        t.timestamps index: true
      end
    end
  end

  def create_siblings_decoy_items_table
    Temping.create :siblings_decoy_items do
      include Hierarchable
      hierarchable parent_source: :siblings_test_hierarchy_parent

      belongs_to :siblings_test_hierarchy_parent

      with_columns do |t|
        t.integer :siblings_test_hierarchy_parent_id
        t.string :name, null: false
        t.references :hierarchy_root,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_sibs_test_decoy_items_on_hierarchy_root'
                     }
        t.references :hierarchy_parent,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_sibs_test_decoy_items_on_hierarchy_parent'
                     }
        t.string :hierarchy_ancestors_path,
                 index: { name: 'idx_sibs_test_decory_items_on_hierarchy_path' }
        t.timestamps index: true
      end
    end
  end
end
