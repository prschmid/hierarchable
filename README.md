# Hierarchable

[![CircleCI](https://dl.circleci.com/status-badge/img/gh/prschmid/hierarchable/tree/main.svg?style=shield)](https://dl.circleci.com/status-badge/redirect/gh/prschmid/hierarchable/tree/main)

A simple way to define cross model hierarchical (parent, child, sibling) relationships between ActiveRecord models.

The aim of this library is to efficiently create and store the ancestors of an object so that it is easy to generate things like breadcrumbs that require information about an object's ancestors that may span multiple models (e.g. `Project` and `Task`). It is designed in such a way that each object contains the ancestry information and that no joins need to be made to a separate table to get this ancestry information.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'hierarchable'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install hierarchable

Once the gem is installed, you will need to make sure that your models have the correct columns.

* hierarchy_root: The root node in the hierarchy hierarchy (polymorphic)
* hierarchy_parent: The parent of the current object (polymorphic)
* hierarchy_ancestors_path: The string representation of all ancestors of
                            the current object (string).

Assuming that you are using UUIDs for your IDs, this can be done by adding the following to the model(s) for which you wish to have hierarchy information:

```
t.references :hierarchy_root,
             polymorphic: true,
             null: true,
             type: :uuid,
             index: true
t.references :hierarchy_parent,
             polymorphic: true,
             null: true,
             type: :uuid,
             index: true
t.string :hierarchy_ancestors_path, index: true
```

If you aren't using UUIDs, then simply omit the `type: :uuid` from the two `references` definitions.

Note, the `hierarchy_ancestors_path` column does contain all of the information that is in the `hierarchy_root` and `hierarchy_parent` columns, but those two columns are created for more efficient querying as the direct parent and the root are the most frequent parts of the hierarchy that are needed.

## Usage

### Getting Started

We will describe the usage using a simplistic Project and Task analogy where we assume that a Project can have many tasks. Given a class `Project` we can set it up as follows

```ruby
class Project
  include Hierarchable
  hierarchable
  # If desired, could explicitly setting the parent source to `nil`, but this is
  # the same "under the hood"
  # hierarchable parent_source: nil
end
```

This will set up the `Project` as the root of the hierarchy. When a `Project` model is saved, it will not have any values for the hierarchy_root, hierarchy_parent, or hierarchy_ancestors_path. This is because for the root item as we are not guaranteed to have an ID for the object until after it is saved, and so there is no way for us to set these values in a consistent way across different use cases. This doesn't affect any of the usage of the library, it's just something to keep in mind.

```ruby
project = Project.create!

# These will be true. 
project.hierarchy_root == nil
project.hierarchy_parent == nil
project.hierarchy_ancestors_path == ''
```

Now that we have a project configured, we can add tasks that have projects as a parent.

```ruby
class Task
  include Hierarchable
  hierarchable parent_source: :project

  belongs_to :project
end
```

This will configure the hierarchy to look at the project association and use that to compute the parent. So now when we instantiate a task, the parent and root of that task will be the project.

```ruby
project = Project.create!
task = Task.create!(project: project)

# These will be true (assuming that the xxxxxx and yyyyyy are the IDs for the
# project and task respectively)
task.hierarchy_root == project
task.hierarchy_parent == project
task.hierarchy_ancestors_path == 'Project|xxxxxx/Task|yyyyyy'
```

Now, let's assume that our tasks can also have other Tasks as subtasks. Once we do that, we need to ensure that the parent of a subtask is the task and not the project. For this we, can do something like the following:

```ruby
class Task
  include Hierarchable
  hierarchable parent_source: ->(object) {
    obj.parent_task.present? ? :parent_task : :project
  }

  belongs_to :project
  belongs_to :parent_task,
             class_name: 'Task',
             optional: true
  has_many :sub_tasks,
           class_name: 'Task',
           foreign_key: :parent_task
           inverse_of: :parent_task,
           dependent: :destroy
end
```

What we have done here is configured the source attribute for the hierarchy computation to be `:parent_task` if the task has a `parent_task` set (i.e. it's a subtask), or use `:project` if one is not set (i.e. it's a top level task).

```ruby
project = Project.create!
task = Task.create!(project: project)
sub_task = Task.create!(project: project, parent_task: task)

# These will be true
sub_task.hierarchy_root == project
sub_task.hierarchy_parent == task
sub_task.hierarchy_ancestors_path == 'Project|xxxxxx/Task|yyyyyy/Task|zzzzzz'
```

### Core functionality

The core methods that are of interest are the following:

```ruby
project.hierarchy_ancestors
project.hierarchy_parent
project.hierarchy_siblings
project.hierarchy_children
project.hierarchy_descendants
```

The major distinction for what is returned is whether you are querying "up the hierarchy" or "down the hierarchy". As there is only 1 path up the hierchy to get to the root, the return values of `hierarchy_ancestors` is a list and `hierarchy_parent` is a single object. However, traversing down the list is a little more tricky as there are various models and potential paths to get all the way do to the leaves. As such, for all methods at the same level or going down the tree (`hierarchy_siblings`, `hierarchy_children`, and `hierarchy_descendants`), the return value is a hash that has the model class as the key, and either a `ActiveRecord::Relation` or a list as the value. For example, for a Project model that has tasks and milestones as descendants, the return value might be something like

```
{
  'Task': [all descendant tasks starting at the project]
  'Milestone': [all descendant milestones starting at the project]
}
```
Given the architecture of this library, this is the most efficient way to return all objects with as few queries as possible.

#### Limiting the objects returned

All of the methods (except `hierarchy_parent`) take a `models` paramter that can be used to limit the results returned. The potential values are 

* `:all` (default): Return all objects regardless of type
* `:this`: Return only objects of the SAME time as the current object
* An array of models of interest: Return only the objects of the type(s) that are specified (e.g. [`Project`] or [`Project`, `Task`]). The models can be passed either as class objects or a string that can be turned into a class object via `safe_constantize`.

There are times when we only need to get the siblings/children/descendants of one type and having a hash returned is a little cumbersome. To deal with this case, you can pass `compact: true` as a parameter and it will return just single result not as a hash. For example:

```
# Returns as a hash of the form `{Task: [..all descendants..]}`
project.hierarch_descendants(models: ['Task'])

# Returns just the result: `[..all descendants..]`
project.hierarch_descendants(models: ['Task'], compact: true)
```
### Working with siblings and descendants of an object

Let's continue with our `Project` and `Task` example from above and assume we have the following models:

```ruby
class Project
  include Hierarchable
  hierarchable
end

class Task
  include Hierarchable
  hierarchable parent_source: :project

  belongs_to :project
end

class Milestone
  include Hierarchable
  hierarchable parent_source: :project

  belongs_to :project
end
```

Based on this setup, we can get all siblings and descendants of either a `Project` or `Task` as follows:

```ruby
project = Project.create!
task = Task.create!(project: project)
milestone = Milestone.create!(project: project)

# Query for all Project objects that are siblings of this project.
# Since the project is the root of the hierarchy, this will return no siblings
project.hierarchy_siblings

# Query for all objects (regardless of type) that are descendats of this project
# In our example, this will return all Tasks and Milestones
project.hierarchy_descendants

# Query for all Project objects that are descendats of this project
# In our example, this will return no results
project.hierarchy_descendants(models: :this)

# Query for all Task objects that are siblings of this task.
# This will return all tasks and milestones that are part of the project
task.hierarchy_siblings
```

In order to figure out the potential descendants of an object we need to inspect the object and query all relations to to see if any of those have this object as an ancestor. In many cases these relations can be inferred correctly by getting all of the `has_many` relationships that a model has defined. To be safe and not return potential duplicate associations, the only associations that are automatically detected are the ones that are the pluralized form of the model name. 

```ruby
class Project
  has_many :tasks
  has_many :completed_tasks, -> { completed }, class_name: 'Task'
  has_many :timestamps, class_name: 'MetricLibrary::Timestamp`
end
```

In the `Project` model defined above, only the `:tasks` association will be used for finding descendants.

However there are times when we need to manually add a child relation to be inspected. This can be done in one of two ways. The most common case is if we want to specify additional associations. This will take all of the associations that can be auto-detected and also add in the one provided.

```ruby
class SomeObject
  include Hierarchable
  hierarched parent_source: :parent,
             additional_descendant_associations: [:some_association]
end
```

There may also be a case when we want exact control over what associations that should be used. In that case, we can specify it like this:

```ruby
class SomeObject
  include Hierarchable
  hierarched parent_source: :parent,
             descendant_associations: [:some_association]
end
```

Note: For the use case that this library was designed (e.g. creating breadcrumbs) this was a limitation that was perfectly acceptible. In the future we may plan to letusers create an optional "ancestry" table to make this more efficient. Once this table exists, inserts and updates will be slower as an extra object will need to be managed, but queries descenants will be improved.

### Configuring the separators

By default the separators to use for the path and records are `/` and `|` respectively. This means that a hierarchy path will look something like

```
<record1_type>|<record1_id>/<record2_type>|<record2_id>
```

In the event you need to modify the separators used to build the path, you can pass in your desired separators:

```ruby
class SomeObject
  include Hierarchable
  hierarchable parent_source: :parent_object,
               path_separator: '@@',
               record_separator: '++'
  
  belongs_to :parent_object
end
```

Assuming that you set the separators like that for all models, then your path will look something like
```
<record1_type>++<record1_id>@@<record2_type>++<record2_id>
```

CAUTION: When setting custom path and/or record separators, do not use any characters that are likely to be in class/module names such as -, _, :, etc. Otherwise it will not be possible to determine the objects in the path.

# Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/prschmid/hierarchable.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
