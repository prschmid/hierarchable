# frozen_string_literal: true

require 'test_helper'
require 'temping'

class SetHierarchyParentTest < Minitest::Test
  def setup
    create_hierarchable_test_roots_table
    create_hierarchable_test_parents_table
    create_hierarchable_test_kids_table
  end

  delegate :teardown, to: :Temping

  def test_assigns_parent_to_nil_if_object_is_root
    root = HierarchableTestRoot.new

    assert_nil root.hierarchy_root
    assert_nil root.hierarchy_parent
    assert_nil root.hierarchy_parent(raw: true)

    root.send(:set_hierarchy_parent)

    assert_nil root.hierarchy_root
    assert_nil root.hierarchy_parent
    assert_nil root.hierarchy_parent(raw: true)
  end

  def test_assigns_parent_equal_to_parent_if_parent_is_root
    root = HierarchableTestRoot.create!

    assert_nil root.hierarchy_root
    assert_nil root.hierarchy_parent
    assert_nil root.hierarchy_parent(raw: true)

    parent = HierarchableTestParent.new
    parent.hierarchable_test_root = root

    assert_nil parent.hierarchy_root
    assert_equal root, parent.hierarchy_parent
    assert_nil parent.hierarchy_parent(raw: true)

    parent.send(:set_hierarchy_parent)

    assert_equal root, parent.hierarchy_parent
    assert_equal root, parent.hierarchy_parent(raw: true)
    assert_equal parent.hierarchable_test_root, root
  end

  def test_assigns_parent_equal_if_source_is_a_function
    create_hierarchable_test_parents_using_anonymous_function_table

    root = HierarchableTestRoot.create!

    assert_nil root.hierarchy_root
    assert_nil root.hierarchy_parent
    assert_nil root.hierarchy_parent(raw: true)

    parent = HierarchableTestAnonFuncParent.new
    parent.hierarchable_test_root = root

    assert_nil parent.hierarchy_root
    assert_equal root, parent.hierarchy_parent
    assert_nil parent.hierarchy_parent(raw: true)

    parent.send(:set_hierarchy_parent)

    assert_equal root, parent.hierarchy_parent
    assert_equal root, parent.hierarchy_parent(raw: true)
    assert_equal parent.hierarchable_test_root, root
  end

  def test_assigns_parent_equal_to_parent_if_deeply_nested
    root = HierarchableTestRoot.create!
    parent = HierarchableTestParent.create!(hierarchable_test_root: root)

    kid = HierarchableTestKid.new
    kid.hierarchable_test_parent = parent

    assert_equal parent, kid.hierarchy_parent
    assert_nil kid.hierarchy_parent(raw: true)

    kid.send(:set_hierarchy_parent)
    kid.send(:set_hierarchy_root)

    assert_equal parent, kid.hierarchy_parent
    assert_equal parent, kid.hierarchy_parent(raw: true)
    assert_equal root, parent.hierarchy_parent
    assert_equal root, parent.hierarchy_parent(raw: true)
    assert_nil root.hierarchy_parent
    assert_nil root.hierarchy_parent(raw: true)
  end

  def test_does_not_assign_parent_if_record_does_not_have_a_parent_attribute
    root = HierarchableTestRoot.new

    assert_respond_to root, :hierarchy_parent_source
    assert_nil root.hierarchy_parent
    assert_nil root.hierarchy_parent(raw: true)

    root.send(:set_hierarchy_parent)

    assert_nil root.hierarchy_parent
    assert_nil root.hierarchy_parent(raw: true)
  end

  private

  def create_hierarchable_test_parents_using_anonymous_function_table
    Temping.create :hierarchable_test_anon_func_parents do
      include Hierarchable

      hierarchable parent_source: ->(_obj) { :hierarchable_test_root }

      belongs_to :hierarchable_test_root, optional: true

      with_columns do |t|
        t.integer :hierarchable_test_root_id
        t.string :name
        t.references :hierarchy_root,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_hierarchable_test_anon_func_parents_' \
                             'on_hierarchy_root'
                     }
        t.references :hierarchy_parent,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_hierarchable_test_anon_func_parents_' \
                             'on_hierarchy_parent'
                     }
        t.string :hierarchy_ancestors_path,
                 index: {
                   name: 'idx_hierarchable_test_anon_func_parents_' \
                         'on_ancestors_path'
                 }
      end
    end
  end
end
