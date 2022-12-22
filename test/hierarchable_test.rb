# frozen_string_literal: true

require 'test_helper'
require 'temping'

class HierarchableTest < Minitest::Test
  def setup
    create_hierarchable_test_roots_table
    create_hierarchable_test_parents_table
    create_hierarchable_test_kids_table
  end

  def teardown
    Temping.teardown
  end

  def test_that_it_has_a_version_number
    refute_nil ::Hierarchable::VERSION
  end

  def test_ancestors_should_return_array_of_ancestor_records
    root = HierarchableTestRoot.create!

    assert_empty root.all_ancestors

    parent = HierarchableTestParent.create!(hierarchable_test_root: root)

    assert_equal [root], parent.all_ancestors

    kid = HierarchableTestKid.create!(hierarchable_test_parent: parent)

    assert_equal [root, parent], kid.all_ancestors
  end

  def test_to_hierarchy_ancestors_path_format_for_new_and_existing_records
    # Regardless of what the objects are, if they don't have the parent
    # attribute set, we should always get an "" if it's a new object and
    # the hierarchy_ancestors_path with just the object in it if it has been
    # saved.

    root = HierarchableTestRoot.new

    assert_equal '', root.to_hierarchy_ancestors_path_format
    root.save!

    assert_equal "HierarchableTestRoot|#{root.id}",
                 root.to_hierarchy_ancestors_path_format

    parent = HierarchableTestParent.new

    assert_equal '', parent.to_hierarchy_ancestors_path_format
    parent.save!

    assert_equal "HierarchableTestParent|#{parent.id}",
                 parent.to_hierarchy_ancestors_path_format

    kid = HierarchableTestKid.new

    assert_equal '', kid.to_hierarchy_ancestors_path_format
    kid.save!

    assert_equal "HierarchableTestKid|#{kid.id}",
                 kid.to_hierarchy_ancestors_path_format
  end

  def test_hierarchy_full_path_for_new_and_existing_records
    # Regardless of what the objects are, if they don't have the parent
    # attribute set, we should always get an "" if it's a new object and
    # the full hierarchy path once it has been saved.

    root = HierarchableTestRoot.new

    assert_equal '', root.hierarchy_full_path
    root.save!

    assert_equal "HierarchableTestRoot|#{root.id}", root.hierarchy_full_path

    parent = HierarchableTestParent.new(hierarchable_test_root: root)

    assert_equal '', parent.hierarchy_full_path
    parent.save!

    assert_equal "HierarchableTestRoot|#{root.id}/" \
                 "HierarchableTestParent|#{parent.id}",
                 parent.hierarchy_full_path

    kid = HierarchableTestKid.new(hierarchable_test_parent: parent)

    assert_equal '', kid.hierarchy_full_path
    kid.save!

    assert_equal "HierarchableTestRoot|#{root.id}/" \
                 "HierarchableTestParent|#{parent.id}/" \
                 "HierarchableTestKid|#{kid.id}",
                 kid.hierarchy_full_path
  end
end
