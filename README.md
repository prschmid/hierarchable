# Hierarchable

[![CircleCI](https://dl.circleci.com/status-badge/img/gh/prschmid/hierarchable/tree/main.svg?style=shield)](https://dl.circleci.com/status-badge/redirect/gh/prschmid/hierarchable/tree/main)

Cross model hierarchical (parent, child, sibling) relationship between ActiveRecord models.

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

The `hierarchy_ancestors_path` column does contain all of the information that is in the `hierarchy_root` and `hierarchy_parent` columns, but those two columns are created for more efficient querying as the direct parent and the root are the most frequent parts of the hierarchy that are needed.

## Usage

We will describe the usage using a simplistic Project and Task analogy where we assume that a Project can have many tasks. Given a class `Project` we can set it up as follows

```ruby
class Project
  include Hierarchable
  hierarchable
end
```

This will set up the `Project` as the root of the hierarchy. This means that when we query for its root or parent, it will return "self". I.e.

```ruby
project = Project.create!

# These will be true (assuming the the ID of the project is the UUID xxxxxxxx-...)
project.hierarchy_root == project
project.hierarchy_parent == project
project.hierarchy_ancestors_path == 'Project|xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
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

# These will be true
task.hierarchy_root == project
task.hierarchy_parent == project
project.hierarchy_ancestors_path == 'Project|xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
task.hierarchy_root == project
task.hierarchy_parent == project
task.hierarchy_ancestors_path == 'Project|xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/Task|yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy'
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
task.hierarchy_root == project
task.hierarchy_parent == project
project.hierarchy_ancestors_path == 'Project|xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
task.hierarchy_root == project
task.hierarchy_parent == project
task.hierarchy_ancestors_path == 'Project|xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/Task|yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy'
sub_task.hierarchy_root == project
sub_task.hierarchy_parent == task
sub_task.hierarchy_ancestors_path == 'Project|xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/Task|yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy/Task|zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz'
```

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
