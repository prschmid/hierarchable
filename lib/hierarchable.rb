# frozen_string_literal: true

require 'hierarchable/version'
require File.join(File.dirname(__FILE__), 'hierarchable', 'hierarchable')

ActiveRecord::Base.instance_eval { include Hierarchable }
if defined?(Rails) && Rails.version.to_i < 4
  raise 'This version of hierarchable requires Rails 4 or higher'
end
