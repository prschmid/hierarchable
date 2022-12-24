# frozen_string_literal: true

require 'test_helper'
require 'temping'

class HierarchySiblingsTest < Minitest::Test
  def setup
    create_siblings_test_hierarchy_parents_table
    create_siblings_test_items_table
    create_siblings_test_other_items_table

    @hierarchy_parent = SiblingsTestHierarchyParent.create!(name: 'parent')
    @object = @hierarchy_parent.siblings_test_items.create(name: 'obj')
  end

  def teardown
    Temping.teardown
  end

  def test_should_return_all_siblings_with_self
    sib1 = @hierarchy_parent.siblings_test_items.create(name: 'sib1')
    sib2 = @hierarchy_parent.siblings_test_items.create(name: 'sib2')
    other = @hierarchy_parent.siblings_test_other_items.create(name: 'other')

    siblings = @object.hierarchy_siblings(include_self: true)

    assert_equal \
      %w[SiblingsTestItem SiblingsTestOtherItem].map(&:to_s).sort!,
      siblings.keys.map(&:to_s).sort!

    assert_equal [@object.id, sib1.id, sib2.id].sort!,
                 siblings['SiblingsTestItem'].map(&:id).sort!
    assert_equal [other.id], siblings['SiblingsTestOtherItem'].map(&:id)
  end

  def test_should_return_all_siblings_without_self
    sib1 = @hierarchy_parent.siblings_test_items.create(name: 'sib1')
    sib2 = @hierarchy_parent.siblings_test_items.create(name: 'sib2')
    other = @hierarchy_parent.siblings_test_other_items.create(name: 'other')

    siblings = @object.hierarchy_siblings(include_self: false)

    assert_equal %w[SiblingsTestItem SiblingsTestOtherItem].map(&:to_s).sort!,
                 siblings.keys.map(&:to_s).sort!

    assert_equal [sib1.id, sib2.id].sort!,
                 siblings['SiblingsTestItem'].map(&:id).sort!
    assert_equal [other.id], siblings['SiblingsTestOtherItem'].map(&:id)
  end

  def test_should_return_siblings_of_same_type_with_self
    sib1 = @hierarchy_parent.siblings_test_items.create(name: 'sib1')
    sib2 = @hierarchy_parent.siblings_test_items.create(name: 'sib2')
    @hierarchy_parent.siblings_test_other_items.create(name: 'other')

    siblings = @object.hierarchy_siblings(include_self: true, models: :this)

    assert_equal ['SiblingsTestItem'].map(&:to_s), siblings.keys.map(&:to_s)
    assert_equal [@object.id, sib1.id, sib2.id].sort!,
                 siblings['SiblingsTestItem'].map(&:id).sort!
  end

  def test_should_compact_siblings_of_same_type_with_self
    sib1 = @hierarchy_parent.siblings_test_items.create(name: 'sib1')
    sib2 = @hierarchy_parent.siblings_test_items.create(name: 'sib2')
    @hierarchy_parent.siblings_test_other_items.create(name: 'other')

    siblings = @object.hierarchy_siblings(
      include_self: true, models: :this, compact: true
    )

    assert_equal [@object.id, sib1.id, sib2.id].sort!,
                 siblings.map(&:id).sort!
  end

  def test_should_return_siblings_of_defined_type_with_self
    sib1 = @hierarchy_parent.siblings_test_items.create(name: 'sib1')
    sib2 = @hierarchy_parent.siblings_test_items.create(name: 'sib2')
    other = @hierarchy_parent.siblings_test_other_items.create(name: 'other')

    siblings = @object.hierarchy_siblings(
      include_self: true, models: ['SiblingsTestItem']
    )

    assert_equal ['SiblingsTestItem'].map(&:to_s), siblings.keys.map(&:to_s)
    assert_equal [@object.id, sib1.id, sib2.id].sort!,
                 siblings['SiblingsTestItem'].map(&:id).sort!

    other_siblings = @object.hierarchy_siblings(
      include_self: true, models: ['SiblingsTestOtherItem']
    )

    assert_equal ['SiblingsTestOtherItem'].map(&:to_s),
                 other_siblings.keys.map(&:to_s)
    assert_equal [other.id], other_siblings['SiblingsTestOtherItem'].map(&:id)
  end

  def test_should_return_siblings_of_defined_type_as_class_with_self
    sib1 = @hierarchy_parent.siblings_test_items.create(name: 'sib1')
    sib2 = @hierarchy_parent.siblings_test_items.create(name: 'sib2')
    @hierarchy_parent.siblings_test_other_items.create(name: 'other')

    siblings = @object.hierarchy_siblings(
      include_self: true, models: [SiblingsTestItem]
    )

    assert_equal ['SiblingsTestItem'].map(&:to_s), siblings.keys.map(&:to_s)
    assert_equal [@object.id, sib1.id, sib2.id].sort!,
                 siblings['SiblingsTestItem'].map(&:id).sort!
  end

  def test_should_compact_siblings_of_defined_type_with_self
    sib1 = @hierarchy_parent.siblings_test_items.create(name: 'sib1')
    sib2 = @hierarchy_parent.siblings_test_items.create(name: 'sib2')
    other = @hierarchy_parent.siblings_test_other_items.create(name: 'other')

    siblings = @object.hierarchy_siblings(
      include_self: true, models: ['SiblingsTestItem'], compact: true
    )

    assert_equal [@object.id, sib1.id, sib2.id].sort!,
                 siblings.map(&:id).sort!

    other_siblings = @object.hierarchy_siblings(
      include_self: true, models: ['SiblingsTestOtherItem'], compact: true
    )

    assert_equal [other.id], other_siblings.map(&:id)
  end

  def test_should_return_siblings_of_same_type_without_self
    sib1 = @hierarchy_parent.siblings_test_items.create(name: 'sib1')
    sib2 = @hierarchy_parent.siblings_test_items.create(name: 'sib2')
    @hierarchy_parent.siblings_test_other_items.create(name: 'other')

    siblings = @object.hierarchy_siblings(include_self: false, models: :this)

    assert_equal ['SiblingsTestItem'].map(&:to_s), siblings.keys.map(&:to_s)

    assert_equal [sib1.id, sib2.id].sort!,
                 siblings['SiblingsTestItem'].map(&:id).sort!
  end

  def test_should_return_siblings_of_defined_type_without_self
    sib1 = @hierarchy_parent.siblings_test_items.create(name: 'sib1')
    sib2 = @hierarchy_parent.siblings_test_items.create(name: 'sib2')
    other = @hierarchy_parent.siblings_test_other_items.create(name: 'other')

    siblings = @object.hierarchy_siblings(
      include_self: false, models: ['SiblingsTestItem']
    )

    assert_equal ['SiblingsTestItem'].map(&:to_s), siblings.keys.map(&:to_s)
    assert_equal [sib1.id, sib2.id].sort!,
                 siblings['SiblingsTestItem'].map(&:id).sort!

    other_siblings = @object.hierarchy_siblings(
      include_self: false, models: ['SiblingsTestOtherItem']
    )

    assert_equal ['SiblingsTestOtherItem'].map(&:to_s),
                 other_siblings.keys.map(&:to_s)
    assert_equal [other.id], other_siblings['SiblingsTestOtherItem'].map(&:id)
  end

  private

  def create_siblings_test_hierarchy_parents_table
    Temping.create :siblings_test_hierarchy_parents do
      include Hierarchable
      hierarchable

      has_many :siblings_test_items
      has_many :siblings_test_other_items

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
                       name: 'idx_sibs_test_items_on_hierarchy_root'
                     }
        t.references :hierarchy_parent,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_sibs_test_items_on_hierarchy_parent'
                     }
        t.string :hierarchy_ancestors_path,
                 index: { name: 'idx_sibs_test_items_on_hierarchy_path' }
        t.timestamps index: true
      end
    end
  end

  def create_siblings_test_other_items_table
    Temping.create :siblings_test_other_items do
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
                       name: 'idx_sibs_test_other_items_on_hierarchy_root'
                     }
        t.references :hierarchy_parent,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_sibs_test_other_items_on_hierarchy_parent'
                     }
        t.string :hierarchy_ancestors_path,
                 index: { name: 'idx_sibs_test_decory_items_on_hierarchy_path' }
        t.timestamps index: true
      end
    end
  end
end
