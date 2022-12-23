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
    # rubocop:disable Metrics/MethodLength
    def hierarchable(opts = {})
      class_attribute :hierarchable_config

      # Save the configuration
      self.hierarchable_config = {
        parent_source: opts.fetch(:parent_source, nil),
        additional_descendant_associations: opts.fetch(
          :additional_descendant_associations, []
        ),
        descendant_associations: opts.fetch(:descendant_associations, nil),
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

      scope :hierarchy_descendants_of,
            lambda { |object|
              where(
                'hierarchy_ancestors_path LIKE :hierarchy_ancestors_path',
                hierarchy_ancestors_path: "#{object.hierarchy_full_path}%"
              )
            }

      scope :hierarchy_siblings_of,
            lambda { |object|
              where(
                'hierarchy_parent_type=:parent_type AND ' \
                'hierarchy_parent_id=:parent_id',
                parent_type: object.hierarchy_parent.class.name,
                parent_id: object.hierarchy_parent.id
              )
            }

      include InstanceMethods
    end
  end
  # rubocop:enable Metrics/MethodLength

  # Instance methods to include
  module InstanceMethods
    def hierarchy_root?
      hierarchy_root.nil?
    end

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

    # Get all of the ancestors models
    #
    # The `include_self` parameter can be set to decide where to start the
    # the ancestry search. If set to `false` (default), then it will return
    # all models found starting with the parent of this object. If set to
    # `true`, then it will start with the currect object.
    def hierarchy_ancestor_models(include_self: false)
      return [] unless respond_to?(:hierarchy_ancestors_path)
      return include_self ? [self.class] : [] if hierarchy_ancestors_path.blank?

      models = hierarchy_ancestors_path.split(
        hierarchable_config[:path_separator]
      ).map do |ancestor|
        ancestor_class, = \
          ancestor.split(hierarchable_config[:record_separator])
        ancestor_class.safe_constantize
      end.uniq

      models << self.class if include_self
      models.uniq
    end

    # Get ancestors of the same type for an object.
    #
    # Using the `hierarchy_ancestors_path`, this will iteratively get all
    # ancestor objects and return them as a list.
    #
    # If the `models` parameter is `:all` (default), then the result
    # will contain objects of different types. E.g. if we have a Project,
    # Task, and a Comment, the siblings of a Task may include both Tasks and
    # Comments. If you only need this one particular model's data, then
    # set `models` to `:this`. If you want to specify a specific list of models
    # then that can be passed as a list (e.g. [MyModel1, MyModel2])
    # rubocop:disable Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/PerceivedComplexity
    def hierarchy_ancestors(include_self: false, models: :all)
      return [] unless respond_to?(:hierarchy_ancestors_path)
      return include_self ? [self] : [] if hierarchy_ancestors_path.blank?

      ancestors = hierarchy_ancestors_path.split(
        hierarchable_config[:path_separator]
      ).map do |ancestor|
        ancestor_class, ancestor_id = ancestor.split(
          hierarchable_config[:record_separator]
        )

        next if ancestor_class != self.class.name && models != :all
        next if models.is_a?(Array) && models.exclude?(ancestor_class)

        ancestor_class.safe_constantize.find(ancestor_id)
      end

      ancestors.compact
      ancestors << self if include_self
      ancestors
    end
    # rubocop:enable Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/PerceivedComplexity

    # Get all of the models of the children that this object could have
    #
    # This is based on the models identified in the
    # `hierarchy_descendant_associations` association
    #
    # The `include_self` parameter can be set to decide where to start the
    # the children search. If set to `false` (default), then it will return
    # all models found starting with the for all children. If set to
    # `true`, then it will include the current object's class. Note, this
    # parameter is added here for consistency, but in the case of children
    # models, it is unlikely that `include_self` would be set to `true`
    def hierarchy_children_models(include_self: false)
      return [] unless respond_to?(:hierarchy_descendant_associations)
      if hierarchy_descendant_associations.blank?
        return include_self ? [self.class] : []
      end

      models = hierarchy_descendant_associations.map do |association|
        class_for_association(association)
      end

      models << self.class if include_self
      models.uniq
    end

    # Get the children of an object.
    #
    # For a given object type, return all siblings as a hash such that the key
    # is the model and the value is the list of siblings of that model.
    #
    # If the `models` parameter is `:all` (default), then the result
    # will contain objects of different types. E.g. if we have a Project,
    # Task, and a Comment, the siblings of a Task may include both Tasks and
    # Comments. If you only need this one particular model's data, then
    # set `models` to `:this`. If you want to specify a specific list of models
    # then that can be passed as a list (e.g. [MyModel1, MyModel2])
    #
    # The `include_self` parameter can be set to decide where to start the
    # the children search. If set to `false` (default), then it will return
    # all models found starting with the for all children. If set to
    # `true`, then it will include the current object's class. Note, this
    # parameter is added here for consistency, but in the case of children,
    # it is unlikely that `include_self` would be set to `true`
    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/PerceivedComplexity
    def hierarchy_children(include_self: false, models: :all)
      return {} unless respond_to?(:hierarchy_parent_id)

      result = {}
      hierarchy_descendant_associations.each do |association|
        model = class_for_association(association)

        next unless models == :all ||
                    (models.is_a?(Array) && models.include?(model)) ||
                    (models == :this && instance_of?(model))

        result[model] = public_send(association)
      end

      if include_self
        if result.key?(self.class)
          result[self.class] = result[self.class].or(self.class.where(id:))
        elsif models == :all ||
              models == :this ||
              (models.is_a?(Array) && models.include?(self.class))
          result[self.class] = [self]
        end
      end
      result
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/PerceivedComplexity

    # Get all of the sibling models
    #
    # The `include_self` parameter can be set to decide what to include in the
    # sibling models search. If set to `false` (default), then it will return
    # all models other models that are siblings of the current object. If set to
    # `true`, then it will also include the current object's class.
    def hierarchy_sibling_models(include_self: false)
      return [] unless respond_to?(:hierarchy_parent)
      return include_self ? [self.class] : [] if hierarchy_parent.blank?

      models = hierarchy_parent.hierarchy_children_models(include_self: false)
      models << self.class if include_self
      models.uniq
    end

    # Get siblings of an object.
    #
    # If the `models` parameter is `:all` (default), then the result
    # will contain objects of different types. E.g. if we have a Project,
    # Task, and a Comment, the siblings of a Task may include both Tasks and
    # Comments. If you only need this one particular model's data, then
    # set `models` to `:this`. If you want to specify a specific list of models
    # then that can be passed as a list (e.g. [MyModel1, MyModel2])
    def hierarchy_siblings(include_self: false, models: :all)
      return {} unless respond_to?(:hierarchy_parent_id)

      models = case models
               when Array
                 models
               when :all
                 hierarchy_sibling_models(include_self: true)
               else
                 [self.class]
               end

      result = {}
      models.each do |model|
        query = model.where(
          hierarchy_parent_type: public_send(:hierarchy_parent_type),
          hierarchy_parent_id: public_send(:hierarchy_parent_id)
        )
        query = query.where.not(id:) if model == self.class && !include_self
        result[model] = query
      end
      result
    end

    # Get all of the descendant models for objects that are descendants of
    # the current one.
    #
    # This will make use of the `hierarchy_descendant_associations` to find
    # all models.
    #
    # Unlike `hierarchy_children_models` that only looks at the immediate
    # children of an object, this  method will look at all descenants of the
    # current object and find the models. In other words, this will follow
    # all relationships of all children, and those children's children to
    # get all models that could potentially be descendants of the current
    # model.
    #
    # The `include_self` parameter can be set to decide where to start the
    # the descentant search. If set to `false` (default), then it will return
    # all models found starting with the children of this object. If set to
    # `true`, then it will start with the currect object.
    # rubocop:disable Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/PerceivedComplexity
    def hierarchy_descendant_models(include_self: false)
      return [] unless respond_to?(:hierarchy_descendant_associations)

      if hierarchy_descendant_associations.blank?
        return include_self ? [self.class] : []
      end

      models = []
      models_to_analyze = [self.class]
      until models_to_analyze.empty?

        klass = models_to_analyze.pop
        next if models.include?(klass)

        obj = klass.new
        next unless obj.respond_to?(:hierarchy_descendant_associations)

        models_to_analyze += obj.hierarchy_children_models(include_self: false)

        next if klass == self.class && !include_self

        models << klass
      end
      models.uniq
    end
    # rubocop:enable Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/PerceivedComplexity

    # Get descendants for an object.
    #
    # The `include_self` parameter can be set to decide where to start the
    # the descentant search. If set to `false` (default), then it will return
    # all models found starting with the children of this object. If set to
    # `true`, then it will start with the currect object.
    #
    # If the `models` parameter is `:all` (default), then the result
    # will contain objects of different types. E.g. if we have a Project,
    # Task, and a Comment, the siblings of a Task may include both Tasks and
    # Comments. If you only need this one particular model's data, then
    # set `models` to `:this`. If you want to specify a specific list of models
    # then that can be passed as a list (e.g. [MyModel1, MyModel2])
    # rubocop:disable Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/PerceivedComplexity
    def hierarchy_descendants(include_self: false, models: :all)
      return {} unless respond_to?(:hierarchy_ancestors_path)

      models = case models
               when Array
                 models
               when :all
                 hierarchy_descendant_models(include_self: true)
               else
                 [self.class]
               end

      result = {}
      models.each do |model|
        query = if hierarchy_root?
                  model.where(
                    hierarchy_root_type: self.class.name,
                    hierarchy_root_id: id
                  )
                else
                  path = public_send(:hierarchy_full_path)
                  model.where(
                    'hierarchy_ancestors_path LIKE ?',
                    "#{model.sanitize_sql_like(path)}%"
                  )
                end
        if model == self.class
          query = if include_self
                    query.or(model.where(id:))
                  else
                    query.where.not(id:)
                  end
        end
        result[model] = query
      end
      result
    end
    # rubocop:enable Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/PerceivedComplexity

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

    # Return all of the `has_many` association names this class class has as a
    # list of symbols.
    #
    # In order to be safe and not return potential duplicate associations,
    # the only associations that are automatically
    # detected are the ones that are the pluralized form of the model name.
    # For example, if a model as the association `has_many :tasks`, there
    # will need to be a Task model for this association to be kept.
    #
    # If there are some associations that need to be manually
    # added, one simply needs to specify them when setting up the model.
    #
    # The most common case is if we want to specify additional associations.
    # This will take all of the associations that can be auto-detected and
    # also add in the one provided.
    #
    #   class A
    #     include Hierarched
    #     hierarched parent_source: :parent,
    #                additional_descendant_associations: [:some_association]
    #   end
    #
    # There may also be a case when we want exact control over what associations
    # that should be used. In that case, we can specify it like this:
    #
    #   class A
    #     include Hierarched
    #     hierarched parent_source: :parent,
    #                descendant_associations: [:some_association]
    #   end
    def hierarchy_descendant_associations
      if hierarchable_config[:descendant_associations].present?
        return hierarchable_config[:descendant_associations]
      end

      associations = \
        self.class
            .reflect_on_all_associations(:has_many)
            .reject do |a|
              a.name.to_s.singularize.camelcase.safe_constantize.nil?
            end
            .reject(&:through_reflection?)
            .map(&:name)
      associations += hierarchable_config[:additional_descendant_associations]
      associations.uniq
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

    def class_for_association(association)
      self.association(association)
          .reflection
          .class_name
          .safe_constantize
    end
  end
end
