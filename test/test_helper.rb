# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'minitest/autorun'
require 'active_record'
require 'hierarchable'

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3', database: ':memory:'
)

#
# Define some helper temping tables
#

def create_hierarchable_test_roots_table
  Temping.create :hierarchable_test_roots do
    include Hierarchable

    hierarchable parent_source: nil

    has_many :hierarchable_test_parents

    with_columns do |t|
      t.string :name
      t.references :hierarchy_root,
                   polymorphic: true,
                   null: true,
                   index: {
                     name: 'idx_hierarchable_test_roots_on_hierarchy_root'
                   }
      t.references :hierarchy_parent,
                   polymorphic: true,
                   null: true,
                   index: {
                     name: 'idx_hierarchable_test_roots_on_hierarchy_parent'
                   }
      t.string :hierarchy_ancestors_path, index: true
    end
  end
end

def create_hierarchable_test_parents_table
  Temping.create :hierarchable_test_parents do
    include Hierarchable

    hierarchable parent_source: :hierarchable_test_root

    belongs_to :hierarchable_test_root, optional: true
    has_many :hierarchable_test_kids

    with_columns do |t|
      t.integer :hierarchable_test_root_id
      t.string :name
      t.references :hierarchy_root,
                   polymorphic: true,
                   null: true,
                   index: {
                     name: 'idx_hierarchable_test_parents_on_hierarchy_root'
                   }
      t.references :hierarchy_parent,
                   polymorphic: true,
                   null: true,
                   index: {
                     name: 'idx_hierarchable_test_parents_on_hierarchy_parent'
                   }
      t.string :hierarchy_ancestors_path, index: true
    end
  end
end

def create_hierarchable_test_kids_table
  Temping.create :hierarchable_test_kids do
    include Hierarchable

    hierarchable parent_source: :hierarchable_test_parent

    belongs_to :hierarchable_test_parent, optional: true

    with_columns do |t|
      t.integer :hierarchable_test_parent_id
      t.string :name
      t.references :hierarchy_root,
                   polymorphic: true,
                   null: true,
                   index: {
                     name: 'idx_hierarchable_test_kids_on_hierarchy_root'
                   }
      t.references :hierarchy_parent,
                   polymorphic: true,
                   null: true,
                   index: {
                     name: 'idx_hierarchable_test_kids_on_hierarchy_parent'
                   }
      t.string :hierarchy_ancestors_path, index: true
    end
  end
end
