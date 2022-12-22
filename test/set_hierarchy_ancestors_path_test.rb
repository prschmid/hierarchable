# frozen_string_literal: true

require 'test_helper'
require 'temping'

class SetHierarchyAncestorsPathTest < Minitest::Test
  def setup
    create_hierarchable_test_roots_table
    create_hierarchable_test_parents_table
    create_hierarchable_test_kids_table
  end

  def teardown
    Temping.teardown
  end

  def test_of_root_is_an_empty_hierarchy
    root = HierarchableTestRoot.new

    assert_nil root.hierarchy_ancestors_path
    root.send(:set_hierarchy_parent)
    root.send(:set_hierarchy_ancestors_path)

    assert_nil root.hierarchy_ancestors_path
  end

  def test_sets_hierarchy_to_parent_if_the_parent_is_the_root
    root = HierarchableTestRoot.create!

    assert_nil root.hierarchy_ancestors_path

    parent = HierarchableTestParent.new
    parent.hierarchable_test_root = root

    assert_nil parent.hierarchy_ancestors_path

    parent.send(:set_hierarchy_parent)
    parent.send(:set_hierarchy_ancestors_path)

    assert_equal "HierarchableTestRoot|#{root.id}",
                 parent.hierarchy_ancestors_path
  end

  def test_sets_hierarchy_path_if_deeply_nested
    root = HierarchableTestRoot.create!
    parent = HierarchableTestParent.create!(hierarchable_test_root: root)

    kid = HierarchableTestKid.new
    kid.hierarchable_test_parent = parent

    assert_nil kid.hierarchy_ancestors_path

    kid.send(:set_hierarchy_parent)
    kid.send(:set_hierarchy_ancestors_path)

    assert_equal "HierarchableTestRoot|#{root.id}/" \
                 "HierarchableTestParent|#{parent.id}",
                 kid.hierarchy_ancestors_path
  end
end
