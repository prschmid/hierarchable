# frozen_string_literal: true

require 'test_helper'
require 'temping'

class HierarchyChildrenTest < Minitest::Test
  def setup
    create_children_test_projects_table
    create_children_test_tasks_table
    create_children_test_milestones_table

    @project = ChildrenTestProject.create!(name: 'project')
    @task = ChildrenTestTask.create(
      children_test_project: @project, name: 'task'
    )
  end

  def teardown
    Temping.teardown
  end

  def test_should_return_all_children_without_self_root_of_hierarchy
    children = @project.hierarchy_children(include_self: false)

    assert_equal \
      [ChildrenTestTask, ChildrenTestMilestone].map(&:to_s).sort!,
      children.keys.map(&:to_s).sort!

    assert_equal [@task.id], children[ChildrenTestTask].map(&:id)
    assert_empty children[ChildrenTestMilestone].map(&:id)
  end

  def test_should_return_all_children_with_self_root_of_hierarchy
    children = @project.hierarchy_children(include_self: true)

    assert_equal \
      [ChildrenTestProject, ChildrenTestTask,
       ChildrenTestMilestone].map(&:to_s).sort!,
      children.keys.map(&:to_s).sort!

    assert_equal [@project.id], children[ChildrenTestProject].map(&:id)
    assert_equal [@task.id], children[ChildrenTestTask].map(&:id)
    assert_empty children[ChildrenTestMilestone].map(&:id)
  end

  def test_should_return_this_model_children_with_self_root_of_hierarchy
    children = @project.hierarchy_children(include_self: true, models: :this)

    assert_equal [ChildrenTestProject].map(&:to_s), children.keys.map(&:to_s)
    assert_equal [@project.id], children[ChildrenTestProject].map(&:id)
  end

  def test_should_compact_this_model_children_with_self_root_of_hierarchy
    children = @project.hierarchy_children(
      include_self: true, models: :this, compact: true
    )

    assert_equal [@project.id], children.map(&:id)
  end

  def test_should_return_defined_children_with_self_root_of_hierarchy
    children = @project.hierarchy_children(
      include_self: true, models: [ChildrenTestTask]
    )

    assert_equal [ChildrenTestTask].map(&:to_s), children.keys.map(&:to_s)
    assert_equal [@task.id], children[ChildrenTestTask].map(&:id)
  end

  def test_should_compact_defined_children_with_self_root_of_hierarchy
    children = @project.hierarchy_children(
      include_self: true, models: [ChildrenTestTask], compact: true
    )

    assert_equal [@task.id], children.map(&:id)
  end

  def test_should_return_this_model_children_without_self_root_of_hierarchy
    children = \
      @project.hierarchy_children(include_self: false, models: :this)

    assert_empty children.keys
  end

  def test_should_return_all_children_without_self_middle_of_hierarchy
    subtask = ChildrenTestTask.create(
      children_test_project: @project, name: 'subtask1', parent_task: @task
    )

    children = @task.hierarchy_children(include_self: false)

    assert_equal [ChildrenTestTask].map(&:to_s), children.keys.map(&:to_s)
    assert_equal [subtask.id], children[ChildrenTestTask].map(&:id)
  end

  def test_should_return_all_descendants_with_self_middle_of_hierarchy
    subtask = ChildrenTestTask.create(
      children_test_project: @project, name: 'subtask1', parent_task: @task
    )

    descendants = @task.hierarchy_children(include_self: true)

    assert_equal [ChildrenTestTask].map(&:to_s), descendants.keys.map(&:to_s)
    assert_equal [@task.id, subtask.id].sort!,
                 descendants[ChildrenTestTask].map(&:id).sort!
  end

  def test_should_not_return_children_from_other_subtrees
    subtask = ChildrenTestTask.create(
      children_test_project: @project, name: 'subtask1', parent_task: @task
    )

    another_task = ChildrenTestTask.create(
      children_test_project: @project, name: 'another_task'
    )
    ChildrenTestTask.create(
      children_test_project: @project, name: 'another_subtask1',
      parent_task: another_task
    )

    children = @task.hierarchy_children(include_self: true)

    assert_equal [ChildrenTestTask].map(&:to_s), children.keys.map(&:to_s)
    assert_equal [@task.id, subtask.id].sort!,
                 children[ChildrenTestTask].map(&:id).sort!
  end

  private

  def create_children_test_projects_table
    Temping.create :children_test_projects do
      include Hierarchable
      hierarchable

      has_many :children_test_tasks
      has_many :children_test_milestones

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

  def create_children_test_tasks_table
    Temping.create :children_test_tasks do
      include Hierarchable
      hierarchable parent_source: lambda { |obj|
        obj.parent_task.nil? ? :children_test_project : :parent_task
      }

      belongs_to :children_test_project
      belongs_to :parent_task,
                 class_name: 'ChildrenTestTask',
                 optional: true
      has_many :children_test_tasks,
               class_name: 'ChildrenTestTask',
               foreign_key: 'parent_task_id',
               inverse_of: :parent_task,
               dependent: :destroy

      with_columns do |t|
        t.integer :children_test_project_id
        t.string :name, null: false
        t.integer :parent_task_id, null: true
        t.references :hierarchy_root,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_children_test_tasks_on_hierarchy_root'
                     }
        t.references :hierarchy_parent,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_children_test_tasks_on_hierarchy_parent'
                     }
        t.string :hierarchy_ancestors_path,
                 index: { name: 'idx_children_test_tasks_on_hierarchy_path' }
        t.timestamps index: true
      end
    end
  end

  def create_children_test_milestones_table
    Temping.create :children_test_milestones do
      include Hierarchable
      hierarchable parent_source: lambda { |obj|
        if obj.parent_milestone.nil?
          :children_test_project
        else
          :parent_milestone
        end
      }

      belongs_to :children_test_project
      belongs_to :parent_milestone,
                 class_name: 'ChildrenTestMilestone',
                 optional: true
      has_many :children_test_milestones,
               class_name: 'ChildrenTestMilestone',
               foreign_key: 'parent_milestone_id',
               inverse_of: :parent_milestone,
               dependent: :destroy

      with_columns do |t|
        t.integer :children_test_project_id
        t.string :name, null: false
        t.integer :parent_milestone_id, null: true
        t.references :hierarchy_root,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_children_test_milestones_on_hierarchy_root'
                     }
        t.references :hierarchy_parent,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_children_test_milestones_on_' \
                             'hierarchy_parent'
                     }
        t.string :hierarchy_ancestors_path,
                 index: {
                   name: 'idx_children_test_milestones_on_hierarchy_path'
                 }
        t.timestamps index: true
      end
    end
  end
end
