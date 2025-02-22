# frozen_string_literal: true

require 'test_helper'
require 'temping'

class HierarchyParentChangedTest < Minitest::Test
  def setup
    create_hierarchable_test_roots_table
    create_hierarchable_test_parents_table
    create_hierarchable_test_kids_table
  end

  delegate :teardown, to: :Temping

  def test_does_change_hierarchy_if_parent_is_changed
    root = HierarchableTestRoot.create!
    parent = HierarchableTestParent.create!(hierarchable_test_root: root)

    assert_equal "HierarchableTestRoot|#{root.id}",
                 parent.hierarchy_ancestors_path

    new_root = HierarchableTestRoot.create!
    parent.hierarchable_test_root = new_root
    parent.save!

    assert_equal new_root, parent.hierarchy_parent
    assert_equal new_root, parent.hierarchy_root
    assert_equal "HierarchableTestRoot|#{new_root.id}",
                 parent.hierarchy_ancestors_path
  end

  def test_does_not_change_hierarchy_if_parent_is_unchanged
    root = HierarchableTestRoot.create!
    parent = HierarchableTestParent.create!(hierarchable_test_root: root)

    assert_equal "HierarchableTestRoot|#{root.id}",
                 parent.hierarchy_ancestors_path

    parent.name = 'I am changing my name'
    parent.save!

    assert_equal "HierarchableTestRoot|#{root.id}",
                 parent.hierarchy_ancestors_path
  end

  def test_changes_hierarchy_if_parent_is_changed_same_root_deeply_nested
    root = HierarchableTestRoot.create!
    parent = HierarchableTestParent.create!(hierarchable_test_root: root)
    kid = HierarchableTestKid.create!(hierarchable_test_parent: parent)

    assert_equal "HierarchableTestRoot|#{root.id}/" \
                 "HierarchableTestParent|#{parent.id}",
                 kid.hierarchy_ancestors_path

    new_parent = HierarchableTestParent.create!(hierarchable_test_root: root)
    parent.hierarchable_test_root = root
    parent.save!

    kid.hierarchable_test_parent = new_parent
    kid.save!

    assert_equal new_parent, kid.hierarchy_parent
    assert_equal root, kid.hierarchy_root
    assert_equal "HierarchableTestRoot|#{root.id}/" \
                 "HierarchableTestParent|#{new_parent.id}",
                 kid.hierarchy_ancestors_path
  end

  def test_changes_hierarchy_if_parent_is_changed_different_root_deeply_nested
    root = HierarchableTestRoot.create!
    parent = HierarchableTestParent.create!(hierarchable_test_root: root)
    kid = HierarchableTestKid.create!(hierarchable_test_parent: parent)

    assert_equal "HierarchableTestRoot|#{root.id}/" \
                 "HierarchableTestParent|#{parent.id}",
                 kid.hierarchy_ancestors_path

    new_root = HierarchableTestRoot.create!
    new_parent = HierarchableTestParent.create!(
      hierarchable_test_root: new_root
    )

    kid.hierarchable_test_parent = new_parent
    kid.save!

    assert_equal new_parent, kid.hierarchy_parent
    assert_equal new_root, kid.hierarchy_root
    assert_equal "HierarchableTestRoot|#{new_root.id}/" \
                 "HierarchableTestParent|#{new_parent.id}",
                 kid.hierarchy_ancestors_path
  end
end
