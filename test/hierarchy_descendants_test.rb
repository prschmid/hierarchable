# frozen_string_literal: true

require 'test_helper'
require 'temping'

class HierarchyDescendantsTest < Minitest::Test
  def setup
    create_descendants_test_projects_table
    create_descendants_test_tasks_table
    create_descendants_test_milestones_table

    @project = DescendantsTestProject.create!(name: 'project')
    @task = DescendantsTestTask.create(
      descendants_test_project: @project, name: 'task'
    )
  end

  def teardown
    Temping.teardown
  end

  def test_should_return_all_descendants_without_self_root_of_hierarchy
    descendants = @project.hierarchy_descendants(include_self: false)

    assert_equal \
      %w[DescendantsTestProject DescendantsTestTask
         DescendantsTestMilestone].map(&:to_s).sort!,
      descendants.keys.map(&:to_s).sort!

    assert_empty descendants['DescendantsTestProject'].map(&:id)
    assert_equal [@task.id], descendants['DescendantsTestTask'].map(&:id)
    assert_empty descendants['DescendantsTestMilestone'].map(&:id)
  end

  def test_should_return_all_descendants_with_self_root_of_hierarchy
    descendants = @project.hierarchy_descendants(include_self: true)

    assert_equal \
      %w[DescendantsTestProject DescendantsTestTask
         DescendantsTestMilestone].map(&:to_s).sort!,
      descendants.keys.map(&:to_s).sort!

    assert_equal [@project.id], descendants['DescendantsTestProject'].map(&:id)
    assert_equal [@task.id], descendants['DescendantsTestTask'].map(&:id)
    assert_empty descendants['DescendantsTestMilestone'].map(&:id)
  end

  def test_should_return_this_model_descendants_with_self_root_of_hierarchy
    descendants = \
      @project.hierarchy_descendants(include_self: true, models: :this)

    assert_equal ['DescendantsTestProject'].map(&:to_s),
                 descendants.keys.map(&:to_s)
    assert_equal [@project.id], descendants['DescendantsTestProject'].map(&:id)
  end

  def test_should_compact_this_model_descendants_with_self_root_of_hierarchy
    descendants = @project.hierarchy_descendants(
      include_self: true, models: :this, compact: true
    )

    assert_equal [@project.id], descendants.map(&:id)
  end

  def test_should_return_defined_descendants_with_self_root_of_hierarchy
    descendants = @project.hierarchy_descendants(
      include_self: true, models: ['DescendantsTestTask']
    )

    assert_equal ['DescendantsTestTask'].map(&:to_s),
                 descendants.keys.map(&:to_s)
    assert_equal [@task.id], descendants['DescendantsTestTask'].map(&:id)
  end

  def test_should_return_defined_class_descendants_with_self_root_of_hierarchy
    descendants = @project.hierarchy_descendants(
      include_self: true, models: [DescendantsTestTask]
    )

    assert_equal ['DescendantsTestTask'].map(&:to_s),
                 descendants.keys.map(&:to_s)
    assert_equal [@task.id], descendants['DescendantsTestTask'].map(&:id)
  end

  def test_should_compact_defined_descendants_with_self_root_of_hierarchy
    descendants = @project.hierarchy_descendants(
      include_self: true, models: ['DescendantsTestTask'], compact: true
    )

    assert_equal [@task.id], descendants.map(&:id)
  end

  def test_should_return_this_model_descendants_without_self_root_of_hierarchy
    descendants = \
      @project.hierarchy_descendants(include_self: false, models: :this)

    assert_equal ['DescendantsTestProject'].map(&:to_s),
                 descendants.keys.map(&:to_s)
    assert_empty descendants['DescendantsTestProject'].map(&:id)
  end

  def test_should_return_all_descendants_without_self_middle_of_hierarchy
    subtask = DescendantsTestTask.create(
      descendants_test_project: @project, name: 'subtask1', parent_task: @task
    )

    descendants = @task.hierarchy_descendants(include_self: false)

    assert_equal ['DescendantsTestTask'].map(&:to_s),
                 descendants.keys.map(&:to_s)
    assert_equal [subtask.id], descendants['DescendantsTestTask'].map(&:id)
  end

  def test_should_return_all_descendants_with_self_middle_of_hierarchy
    subtask = DescendantsTestTask.create(
      descendants_test_project: @project, name: 'subtask1', parent_task: @task
    )

    descendants = @task.hierarchy_descendants(include_self: true)

    assert_equal ['DescendantsTestTask'].map(&:to_s),
                 descendants.keys.map(&:to_s)
    assert_equal [@task.id, subtask.id].sort!,
                 descendants['DescendantsTestTask'].map(&:id).sort!
  end

  def test_should_not_return_descendants_from_other_subtrees
    subtask = DescendantsTestTask.create(
      descendants_test_project: @project, name: 'subtask1', parent_task: @task
    )

    another_task = DescendantsTestTask.create(
      descendants_test_project: @project, name: 'another_task'
    )
    DescendantsTestTask.create(
      descendants_test_project: @project, name: 'another_subtask1',
      parent_task: another_task
    )

    descendants = @task.hierarchy_descendants(include_self: true)

    assert_equal ['DescendantsTestTask'].map(&:to_s),
                 descendants.keys.map(&:to_s)
    assert_equal [@task.id, subtask.id].sort!,
                 descendants['DescendantsTestTask'].map(&:id).sort!
  end

  private

  def create_descendants_test_projects_table
    Temping.create :descendants_test_projects do
      include Hierarchable
      hierarchable

      has_many :descendants_test_tasks
      has_many :descendants_test_milestones

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

  def create_descendants_test_tasks_table
    Temping.create :descendants_test_tasks do
      include Hierarchable
      hierarchable parent_source: lambda { |obj|
        obj.parent_task.nil? ? :descendants_test_project : :parent_task
      }

      belongs_to :descendants_test_project
      belongs_to :parent_task,
                 class_name: 'DescendantsTestTask',
                 optional: true
      has_many :children_test_tasks,
               class_name: 'DescendantsTestTask',
               foreign_key: 'parent_task_id',
               inverse_of: :parent_task,
               dependent: :destroy

      with_columns do |t|
        t.integer :descendants_test_project_id
        t.string :name, null: false
        t.integer :parent_task_id, null: true
        t.references :hierarchy_root,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_descendants_test_tasks_on_hierarchy_root'
                     }
        t.references :hierarchy_parent,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_descendants_test_tasks_on_hierarchy_parent'
                     }
        t.string :hierarchy_ancestors_path,
                 index: { name: 'idx_descendants_test_tasks_on_hierarchy_path' }
        t.timestamps index: true
      end
    end
  end

  def create_descendants_test_milestones_table
    Temping.create :descendants_test_milestones do
      include Hierarchable
      hierarchable parent_source: lambda { |obj|
        if obj.parent_milestone.nil?
          :descendants_test_project
        else
          :parent_milestone
        end
      }

      belongs_to :descendants_test_project
      belongs_to :parent_milestone,
                 class_name: 'DescendantsTestMilestone',
                 optional: true
      has_many :children_test_milestones,
               class_name: 'DescendantsTestMilestone',
               foreign_key: 'parent_milestone_id',
               inverse_of: :parent_milestone,
               dependent: :destroy

      with_columns do |t|
        t.integer :descendants_test_project_id
        t.string :name, null: false
        t.integer :parent_milestone_id, null: true
        t.references :hierarchy_root,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_descendants_test_milestones_on_hierarchy_root'
                     }
        t.references :hierarchy_parent,
                     polymorphic: true,
                     null: true,
                     index: {
                       name: 'idx_descendants_test_milestones_on_' \
                             'hierarchy_parent'
                     }
        t.string :hierarchy_ancestors_path,
                 index: {
                   name: 'idx_descendants_test_milestones_on_hierarchy_path'
                 }
        t.timestamps index: true
      end
    end
  end
end
