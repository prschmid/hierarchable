# frozen_string_literal: true

require 'active_support/concern'

# All objects that want to make use of this concern must have three columns
# defined:
#   hierarchy_root: The root node in the hierarchy hierarchy (polymorphic)
#   hierarchy_parent: The parent of the current object (polymorphic)
#   hierarchy_ancestors_path: The string representation of all ancestors of
#                             the current object (string).
# The `hierarchy_ancestors_path` column does contain all of the information
# that is in the `hierarchy_root` and `hierarchy_parent` columns, but those two
# columns are created for more efficient querying as the direct parent and the
# root are the most frequent parts of the hierarchy that are needed.
#
# To set the attribute that should be used as the parent, one needs to set the
# `parent_source` value when including this in a model.
#
#   class A
#     include Hierarchable
#     hierarchable parent_source: :some_column
#   end
#
# If some model doesn't have a parent (e.g. it's the root of the hierarchy)
# then the `parent_source` can be ommited or explicitly set to `nil`
#
#   class B
#     include Hierarchable
#     hierarchable parent_source: nil
#   end
#
#   class AlternateB
#     include Hierarchable
#     hierarchable
#   end
#
# There are times when the parent is dependent on the state of an object. For
# example, let's assume that a Project can have tasks, and that tasks can also
# have tasks (sub tasks). Assuming that the Task model has both `project`
# and `parent_task` attributes, we could define the parent source dynamically
# as follows:
#
#   class Task
#     include Hierarchable
#     hierarchable parent_source: ->(obj) {
#       obj.parent_task.present ? :parent_task : :project
#     }
#   end
#
# By default the separators to use for the path and records are / and |
# respectively. This means that a hierarchy path will look something like
#
#   <record1_type>|<record1_id>/<record2_type>|<record2_id>
#
# A user can change this default behavior by setting the `path_separator` and/or
# `record_seprator` option when including this in a class. For example:
#
#   class Foo
#     include Hierarchable
#     hierachable path_separator: '##', record_separator: '@@'
#   end
#
# CAUTION: When setting custom path and/or record separators, do not use any
# characters that are likely to be in class/module names such as -, _, :, etc.
module Hierarchable
  extend ActiveSupport::Concern

  HIERARCHABLE_DEFAULT_PATH_SEPARATOR = '/'
  HIERARCHABLE_DEFAULT_RECORD_SEPARATOR = '|'

  class_methods do
    def hierarchable(opts = {})
      class_attribute :hierarchable_config

      # Save the configuration
      self.hierarchable_config = {
        parent_source: opts.fetch(:parent_source, nil),
        path_separator: opts.fetch(
          :path_separator, HIERARCHABLE_DEFAULT_PATH_SEPARATOR
        ),
        record_separator: opts.fetch(
          :record_separator, HIERARCHABLE_DEFAULT_RECORD_SEPARATOR
        )
      }

      belongs_to :hierarchy_root, polymorphic: true, optional: true

      belongs_to :hierarchy_parent, polymorphic: true, optional: true
      alias_method :hierarchy_parent_relationship, :hierarchy_parent

      # Set the parent of the current object. This needs to happen first as
      # setting the hierarchy_root and the hierarchy_ancestors_path depends on
      # having the hierarchy_parent set first.
      before_save :set_hierarchy_parent

      # Based on the hierarchy_parent that is set, set the root. This will take
      # the hierarchy_root of the hierarchy_parent.
      before_save :set_hierarchy_root

      # If an object gets moved, we need to ensure that then
      # hierarchy_ancestors_path is updated to ensure that it stays accurate
      before_save :update_dirty_hierarchy_ancestors_path,
                  unless: :new_record?,
                  if: :hierarchy_parent_changed?

      before_create :set_hierarchy_ancestors_path

      scope :descendants_of,
            lambda { |object|
              where(
                'hierarchy_ancestors_path LIKE :hierarchy_ancestors_path',
                hierarchy_ancestors_path: "#{object.hierarchy_full_path}%"
              )
            }

      scope :siblings_of,
            lambda { |object|
              where(
                'hierarchy_parent_type=:parent_type AND hierarchy_parent_id=:parent_id',
                parent_type: object.hierarchy_parent.class.name,
                parent_id: object.hierarchy_parent.id
              )
            }

      include InstanceMethods
    end
  end

  # Instance methods to include
  module InstanceMethods
    def hierarchy_parent(raw: false)
      return hierarchy_parent_relationship if raw

      # Depending on whether or not the object has been saved or not, we need
      # to be smart as to how we try to get the parent. If it's saved, then
      # the `hierarchy_parent` attribute in the model will be set and so we
      # can use the `belongs_to` relationship to get the parent. However,
      # if the parent has changed or the object has yet to be saved, we can't
      # use the relationship to get the parent as the value will not have been
      # set properly yet in the model (since it's a `before_save` hook).
      use_relationship = if persisted?
                           !hierarchy_parent_changed?
                         else
                           false
                         end

      if use_relationship
        hierarchy_parent_relationship
      else
        source = hierarchy_parent_source
        source.nil? ? nil : send(source)
      end
    end

    # Return the attribute name that links this object to its parent.
    #
    # This should return the name of the attribute/relation/etc either as a
    # string or symbol.
    #
    # For example, if this is a Task, then the hierarchy_parent_source is
    # likely the attribute that references the Project this task belongs to.
    # If the method returns nil (the default behavior), the assumption is that
    # this object is the root of the hierarchy.
    def hierarchy_parent_source
      source = hierarchable_config[:parent_source]
      return nil unless source

      source.respond_to?(:call) ? source.call(self) : source
    end

    # Return the string representation of the current object in the format when
    # used as part of a hierarchy.
    #
    # If this is a new record (i.e. not saved yet), this will return "", and
    # will return the string representation of the format once it is saved.
    def to_hierarchy_ancestors_path_format
      return '' if new_record?

      to_hierarchy_format(self)
    end

    # Return the full hierarchy path from the root to this object.
    #
    # Unlike the hierarchy_ancestors_path which DOES NOT include the current
    # object in the path, this path contains both the ancestors path AND
    # the current object.
    def hierarchy_full_path
      return '' if new_record? ||
                   !respond_to?(:hierarchy_ancestors_path)

      if hierarchy_ancestors_path.present?
        format('%<path>s%<sep>s%<current>s',
               path: hierarchy_ancestors_path,
               sep: hierarchable_config[:path_separator],
               current: to_hierarchy_ancestors_path_format)
      else
        to_hierarchy_ancestors_path_format
      end
    end

    # Return hierarchy path for given list of objects

    def hierarchy_path_for(objects)
      return '' if objects.blank?

      objects.map do |obj|
        to_hierarchy_format(obj)
      end.join(hierarchable_config[:path_separator])
    end

    def to_hierarchy_format(object)
      "#{object.class}#{hierarchable_config[:record_separator]}#{object.id}"
    end

    # Return the full hierarchy path from the root to this object as objects.
    #
    # Unlike the hierarchy_full_path that returns a string of the path,
    # this returns a list of items. The pattern of the returned list will be
    #
    #   [Class, Object, Class, Object, ...]
    #
    # Where the Class is the class of the object coming right after it. This
    # representation is useful when creating a breadcrumb and we want to
    # have both all the ancestors (like in the ancestors method), but also
    # the collections (classes), so that we can build up a nice path with
    # links.
    def hierarchy_full_path_reified
      return '' if new_record? ||
                   !respond_to?(:hierarchy_ancestors_path)

      path = []
      hierarchy_full_path.split(hierarchable_config[:path_separator])
                         .each do |record|
        ancestor_class_name, ancestor_id = record.split(
          hierarchable_config[:record_separator]
        )
        ancestor_class = ancestor_class_name.safe_constantize
        path << ancestor_class
        path << ancestor_class.find(ancestor_id)
      end
      path
    end

    # Get ancestors of the same type for an object.
    #
    # For a given object type, return all ancestors that have the same type.
    # Note, since ancestors may be of different types, this may skip parts
    # of the hierarchy if the particular ancestor happens to be of a different
    # type.
    def ancestors
      return [] if !respond_to?(:hierarchy_ancestors_path) ||
                   hierarchy_ancestors_path.blank?

      a = hierarchy_ancestors_path.split(
        hierarchable_config[:path_separator]
      ).map do |ancestor|
        ancestor_class, ancestor_id = ancestor.split(
          hierarchable_config[:record_separator]
        )

        if ancestor_class == self.class.name
          ancestor_class.safe_constantize.find(ancestor_id)
        end
      end
      a.compact
    end

    # Return the list of all ancestor objects for the current object
    #
    # Using the `hierarchy_ancestors_path`, this will iteratively get all
    # ancestor objects and return them as a list.
    #
    # As there may be ancestors of different types, this is not a single query
    # and may return things of many different types. E.g. if we have a Project,
    # Task, and a Comment, the ancestors of a coment may be the Task and the
    # Project.
    def all_ancestors
      return [] if !respond_to?(:hierarchy_ancestors_path) ||
                   hierarchy_ancestors_path.blank?

      hierarchy_ancestors_path.split(
        hierarchable_config[:path_separator]
      ).map do |ancestor|
        ancestor_class, ancestor_id = ancestor.split(
          hierarchable_config[:record_separator]
        )
        ancestor_class.safe_constantize.find(ancestor_id)
      end
    end

    # Get siblings of the same type for an object.
    #
    # For a given object type, return all siblings. Note, this DOES NOT return
    # siblings of different types and those need to be queried separetly.
    # equivalent to c.hierarchy_parent.children
    #
    # Params:
    # +include_self+:: Whether or not to include self in the list.
    #                  Default is true
    def siblings(include_self: true)
      # The method should always return relation, not an Array sometimes and
      # Relation the other
      return self.class.none unless respond_to?(:hierarchy_parent_id)

      query = self.class.where(
        hierarchy_parent_type: public_send(:hierarchy_parent_type),
        hierarchy_parent_id: public_send(:hierarchy_parent_id)
      )
      query = query.where.not(id:) unless include_self
      query
    end

    # Get all siblings of this object regardless of object type.
    #
    # This has yet to be implemented and would likely require a separate join
    # table that has all of the data across all tables linked to the particular
    # parent. I.e. a simple table that has parent, child in it that we could
    # use to query.
    #
    # Params:
    # +include_self+:: Whether or not to include self in the list.
    #                  Default is true
    def all_siblings
      raise NotImplementedError
    end

    protected

    # Set the hierarchy_parent of the current object.
    #
    # This will look at the `hierarchy_parent_source` and take the value that
    # is returned by that method and use it to set the parent. If the parent
    # is set to `nil`, the assumption is that this object is then the root of
    # the hierarchy.
    def set_hierarchy_parent
      return unless respond_to?(:hierarchy_parent_id)
      return if hierarchy_parent_source.blank?

      self.hierarchy_parent = public_send(hierarchy_parent_source)
    end

    # Set the hierarchy_root of the current object.
    #
    # This will look at the `hierarchy_parent` and take the `hierarchy_root` of
    # that object. Since this looks at the `hierarchy_parent`, it is imperative
    # that the `hierarchy_parent` is set before this method is called.
    def set_hierarchy_root
      return unless respond_to?(:hierarchy_root_id) &&
                    respond_to?(:hierarchy_parent_id)

      parent = hierarchy_parent
      self.hierarchy_root = if parent.respond_to?(:hierarchy_root)
                              if parent.hierarchy_root.nil?
                                parent
                              else
                                parent.hierarchy_root
                              end
                            else
                              parent
                            end
    end

    # Set the hierarchy_ancestors_path of the current object.
    #
    # Based on the hierarchy_parent, this will append the necessary information
    # to update the hierarchy_ancestors_path
    def set_hierarchy_ancestors_path
      return unless respond_to?(:hierarchy_ancestors_path)
      return unless respond_to?(:hierarchy_parent)

      parent = hierarchy_parent
      self.hierarchy_ancestors_path = \
        if parent.nil? || !parent.respond_to?(:hierarchy_ancestors_path)
          nil
        elsif parent.hierarchy_ancestors_path.blank?
          parent.to_hierarchy_ancestors_path_format
        else
          format('%<path>s%<sep>s%<current>s',
                 path: parent.hierarchy_ancestors_path,
                 sep: hierarchable_config[:path_separator],
                 current: parent.to_hierarchy_ancestors_path_format)
        end
    end

    # Check to see if the hierarchy_parent has changed
    #
    # This will take the `hierarchy_parent_source` and check to see if the
    # current objects's value for the ID corresponding to the
    # `hierarchy_parent_source` has been updated.
    def hierarchy_parent_changed?
      # FIXME: We need to figure out how to deal with updating the
      # object_hierarchy_ancestry_path, object_hierarchy_full_path, etc.,
      if hierarchy_parent_source.present?
        public_send("#{hierarchy_parent_source}_id_changed?")
      else
        false
      end
    end

    # Update the hierarchy_ancestors_path if the hierarchy has changed.
    def update_dirty_hierarchy_ancestors_path
      set_hierarchy_ancestors_path
    end
  end
end
