# frozen_string_literal: true

require 'test_helper'
require 'temping'

class HierarchableTest < Minitest::Test
  def setup
    create_hierarchable_test_roots_table
    create_hierarchable_test_parents_table
    create_hierarchable_test_kids_table
  end

  delegate :teardown, to: :Temping

  def test_that_it_has_a_version_number
    refute_nil ::Hierarchable::VERSION
  end

  def test_can_get_hierarchy_ancestor_models
    root = HierarchableTestRoot.new
    parent = HierarchableTestParent.new(hierarchable_test_root: root)
    kid = HierarchableTestKid.new(hierarchable_test_parent: parent)

    # This method depends on the ancestor_path being set, which happens before
    # the object is saved. So, before saving it, this returns nothing
    assert_empty root.hierarchy_ancestor_models
    assert_empty parent.hierarchy_ancestor_models
    assert_empty kid.hierarchy_ancestor_models

    root.save!
    parent.save!
    kid.save!

    assert_empty root.hierarchy_ancestor_models
    assert_equal [HierarchableTestRoot],
                 parent.hierarchy_ancestor_models
    assert_equal [HierarchableTestRoot, HierarchableTestParent],
                 kid.hierarchy_ancestor_models
  end

  def test_can_get_hierarchy_ancestor_models_including_self
    root = HierarchableTestRoot.new
    parent = HierarchableTestParent.new(hierarchable_test_root: root)
    kid = HierarchableTestKid.new(hierarchable_test_parent: parent)

    # This method depends on the ancestor_path being set, which happens before
    # the object is saved. So, before saving it, this returns just this
    # object's class
    assert_equal [HierarchableTestRoot],
                 root.hierarchy_ancestor_models(include_self: true)
    assert_equal [HierarchableTestParent],
                 parent.hierarchy_ancestor_models(include_self: true)
    assert_equal [HierarchableTestKid],
                 kid.hierarchy_ancestor_models(include_self: true)

    root.save!
    parent.save!
    kid.save!

    assert_equal [HierarchableTestRoot],
                 root.hierarchy_ancestor_models(include_self: true)
    assert_equal [HierarchableTestRoot, HierarchableTestParent],
                 parent.hierarchy_ancestor_models(include_self: true)
    assert_equal [HierarchableTestRoot, HierarchableTestParent,
                  HierarchableTestKid],
                 kid.hierarchy_ancestor_models(include_self: true)
  end

  def test_can_get_hierarchy_ancestors
    root = HierarchableTestRoot.new
    parent = HierarchableTestParent.new(hierarchable_test_root: root)
    kid = HierarchableTestKid.new(hierarchable_test_parent: parent)

    # This method depends on the ancestor_path being set, which happens before
    # the object is saved. So, before saving it, this returns nothing
    assert_empty root.hierarchy_ancestors
    assert_empty parent.hierarchy_ancestors
    assert_empty kid.hierarchy_ancestors

    root.save!
    parent.save!
    kid.save!

    assert_empty root.hierarchy_ancestors
    assert_equal [root], parent.hierarchy_ancestors
    assert_equal [root, parent], kid.hierarchy_ancestors
  end

  def test_can_get_hierarchy_ancestors_including_self
    root = HierarchableTestRoot.new
    parent = HierarchableTestParent.new(hierarchable_test_root: root)
    kid = HierarchableTestKid.new(hierarchable_test_parent: parent)

    # This method depends on the ancestor_path being set, which happens before
    # the object is saved. So, before saving it, this returns nothing
    assert_equal [root], root.hierarchy_ancestors(include_self: true)
    assert_equal [parent], parent.hierarchy_ancestors(include_self: true)
    assert_equal [kid], kid.hierarchy_ancestors(include_self: true)

    root.save!
    parent.save!
    kid.save!

    assert_equal [root], root.hierarchy_ancestors(include_self: true)
    assert_equal [root, parent], parent.hierarchy_ancestors(include_self: true)
    assert_equal [root, parent, kid],
                 kid.hierarchy_ancestors(include_self: true)
  end

  def test_can_get_hierarchy_descendant_models
    root = HierarchableTestRoot.new
    parent = HierarchableTestParent.new
    kid = HierarchableTestKid.new

    assert_equal [HierarchableTestParent, HierarchableTestKid],
                 root.hierarchy_descendant_models
    assert_equal [HierarchableTestKid],
                 parent.hierarchy_descendant_models
    assert_empty kid.hierarchy_descendant_models

    root.save!
    parent.save!
    kid.save!

    assert_equal [HierarchableTestParent, HierarchableTestKid],
                 root.hierarchy_descendant_models
    assert_equal [HierarchableTestKid],
                 parent.hierarchy_descendant_models
    assert_empty kid.hierarchy_descendant_models
  end

  def test_can_get_hierarchy_descendant_models_including_self
    root = HierarchableTestRoot.new
    parent = HierarchableTestParent.new
    kid = HierarchableTestKid.new

    assert_equal [HierarchableTestRoot, HierarchableTestParent,
                  HierarchableTestKid],
                 root.hierarchy_descendant_models(include_self: true)
    assert_equal [HierarchableTestParent, HierarchableTestKid],
                 parent.hierarchy_descendant_models(include_self: true)
    assert_equal [HierarchableTestKid],
                 kid.hierarchy_descendant_models(include_self: true)

    root.save!
    parent.save!
    kid.save!

    assert_equal [HierarchableTestRoot, HierarchableTestParent,
                  HierarchableTestKid],
                 root.hierarchy_descendant_models(include_self: true)
    assert_equal [HierarchableTestParent, HierarchableTestKid],
                 parent.hierarchy_descendant_models(include_self: true)
    assert_equal [HierarchableTestKid],
                 kid.hierarchy_descendant_models(include_self: true)
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
