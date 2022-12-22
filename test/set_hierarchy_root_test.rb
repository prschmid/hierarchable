# frozen_string_literal: true

require 'test_helper'
require 'temping'

class SetHierarchyRootTest < Minitest::Test
  def setup
    create_hierarchable_test_roots_table
    create_hierarchable_test_parents_table
    create_hierarchable_test_kids_table
  end

  def teardown
    Temping.teardown
  end

  def test_assigns_root_to_nil_if_object_is_root
    root = HierarchableTestRoot.new

    assert_respond_to root, :hierarchy_parent_source
    assert_nil root.hierarchy_root

    root.send(:set_hierarchy_parent)
    root.send(:set_hierarchy_root)

    assert_nil root.hierarchy_root
  end

  def test_assigns_root_equal_to_parent_if_parent_is_root
    root = HierarchableTestRoot.create!

    assert_nil root.hierarchy_root

    parent = HierarchableTestParent.new
    parent.hierarchable_test_root = root

    assert_respond_to parent, :hierarchy_parent_source
    assert_nil parent.hierarchy_root

    parent.send(:set_hierarchy_parent)
    parent.send(:set_hierarchy_root)

    assert_equal root, parent.hierarchy_root
    assert_equal parent.hierarchable_test_root, parent.hierarchy_root
  end

  def test_assigns_root_if_deeply_nested
    root = HierarchableTestRoot.create!
    parent = HierarchableTestParent.create!(hierarchable_test_root: root)

    kid = HierarchableTestKid.new
    kid.hierarchable_test_parent = parent

    assert_respond_to kid, :hierarchy_parent_source
    assert_nil kid.hierarchy_root

    kid.send(:set_hierarchy_parent)
    kid.send(:set_hierarchy_root)

    assert_equal parent, kid.hierarchy_parent(raw: true)
    assert_equal root, kid.hierarchy_root
    assert_equal kid.hierarchy_parent.hierarchy_root,
                 kid.hierarchy_root
  end
end
