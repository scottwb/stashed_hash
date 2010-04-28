# This extension provides the ability to treat a column as a "stashed hash".
# This will eventually mean a number of things. For now it pretty much
# just means "serialized".
module StashedHash

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    # Tells this class to treat the specified column as a "stashed hash".
    #
    # ====Parameters
    #
    # +col_name+::
    #   The name of the column, as a Symbol or String, to treat as a
    #   "stashed hash".
    #
    # +options+::
    #   An optional Hash of options, supporting the following members:
    #
    #     :initial => The initial value to assign to the stashed hash
    #                 column when a new object is created. Defaults to
    #                 an empty Hash. This will be overridden by parameters
    #                 to the 'new' or 'create' class methods that explicitly
    #                 set this value.
    #
    def stashed_hash(col_name, options = {})
      configuration = {
        :initial => {}
      }
      configuration.update(options) if options.is_a?(Hash)
      
      # REVISIT: This code to validate the columns is problematic because
      #          running the migration to add this column when the code
      #          that calls this already exists, will always fail. I am
      #          just commenting this out for now until I have some time
      #          to think of a better way to do some run-time validation.
      #
      #col_spec = self.columns.find{|c| c.name.to_s == col_name.to_s}
      #if col_spec.nil?
      #  raise "#{col_name.inspect} is not a valid column for #{self.name}"
      #end
      #if col_spec.type != :text
      #  raise "#{col_name.inspect} is not a :text column"
      #end

      class_eval do
        serialize col_name, Hash

        before_create do |obj|
          if obj.send(col_name).nil?
            obj.send("#{col_name}=", configuration[:initial])
          end
          true
        end

        # Gets the value stored in the stashed hash at the specified +key+.
        #
        # This supports nested hash keys. Calling:
        #
        #    obj.get_stash("sports/baseball/stats/RBIs")
        #
        # is equivalent to:
        #
        #    obj.stash['sports']['baseball']['stats']['RBIs']
        #
        # This method is really just for convenience. For example, you may
        # wish to define a constant in your application for a nested
        # key path that you can easily pass to both set_stash and
        # get_stash methods.
        #
        # ====Parameters
        #
        # +key+::
        #   The key of the hash value to get. This should be a String, and
        #   may be delimited into sections with forward-slashes, sort of like
        #   a file path. When slashes are present, this key is treated as a
        #   nested hash key.
        #
        # ====Returns
        #
        # The value found in the stash as the specified key, or +nil+
        # if it was not found.
        #
        define_method("get_#{col_name}".to_sym) do |key|
          (self.send(col_name) || {}).stash_nested_get(key)
        end

        # Deletes the value stored in the stashed hash at the specified +key+.
        #
        # This supports nested hash keys. Calling:
        #
        #   obj.del_stash("sports/baseball/stats/RBIs")
        #
        # is equivalent to:
        #
        #    s = obj.stash['sports']['baseball']['stats']
        #    s.delete('RBIs')
        #    obj.stash = s
        #    obj.save!
        #
        # ====Parameters
        #
        # +key+::
        #   The key of the hash value to delete. This should be a String, and
        #   may be delimited into sections with forward-slashes, sort of like
        #   a file path. When slashes are present, this key is treated as
        #   a nested hash key.
        #
        # ====Returns
        #
        # The value that was deleted from the stash at the specified +key+,
        # or +nil+ if the specified key was not found.
        #
        define_method("del_#{col_name}".to_sym) do |key|
          hash = self.send(col_name)
          return nil if hash.nil? || !hash.is_a?(Hash)
          value = hash.stash_nested_delete(key)
          self.send("#{col_name}=", hash)
          self.save!
          value
        end

        # Sets the stashed hash's member keyed by +key+ to the
        # provided +value+, and immediately saves this change to the database.
        #
        # REVISIT: This is done with wonton disregard for concurrency and
        #          replication latency issues. Eventually when we also
        #          keep a version column, this should:
        #            * Note the current value.
        #            * Perform an OCC-style update.
        #            * Catch a version collision.
        #            * Reload at least this column, if not whole object.
        #            * Test to see if keyed value changed with version change.
        #            * If not, retry.
        #            * If so, raise exception for caller to resolve conflict.
        #
        # REVISIT: Might want to make a version of this that takes an
        #          array of key/value pairs to set all in one save.
        #
        # ====Parameters
        #
        # +key+::
        #   The key of the hash member to set. This should be a String, and
        #   may be delimited into sections with forward-slashes, sort of like
        #   a file path. When slashes are present, this key is treated
        #   as a nested hash key. For example, a key specified as:
        #
        #     "sports/baseball/stats/RBIs"
        #
        #   will actually set the value of:
        #
        #     obj.stash['sports']['baseball']['stats']['RBIs']
        #
        #   member, where 'sports', 'baseball', and 'stats' are all
        #   nested Hashes and created if non-existent.
        #
        # +value+::
        #   The value to set at the specified key.
        #
        # ====Returns
        #
        # The new value assigned to the specified key.
        #
        define_method("set_#{col_name}".to_sym) do |key, value|
          hash = (self.send(col_name) || {})
          hash.stash_nested_set(key, value)
          self.send("#{col_name}=", hash)
          self.save!
          value
        end

        # Modifies the stashed hash's member keyed by +key+ by applying
        # the given block, and immediately saves this change to the database.
        #
        # NOTE: The specified key MUST already exist in order to apply
        #       the block to it to modify it. When it does not already exist
        #       set_stash should be used first to set an initial value.
        #
        # REVISIT: This is built on top of set_stash and the same
        #          REVISIT about safety applies.
        #
        # ====Parameters
        #
        # +key+::
        #   The key of the hash member to modify. This should be a String,
        #   and may be delimited into sections with forward-slashes, sort of
        #   like a file path. When slashes are preset, this key is treated
        #   as a nested hash key. For example, a key specified as:
        #
        #     "sports/baseball/stats/RBIs"
        #
        #   will actually modify the value of:
        #
        #     obj.stash['sports']['baseball']['stats']['RBIs']
        #
        # +func+::
        #   A lambda Proc function to invoke to modify the data.
        #   This Proc takes in the current value and returns the new value
        #   to nest set. IMPORTANT: This block should have no side-effects,
        #   as it may be executed multiple times if necessary to resolve
        #   mid-air collisions.
        #
        #   REVISIT: It would be ideal to make this a regular block to
        #            the method, and that all works great...on Ruby 1.8.7 or
        #            later. In order to keep this working on 1.8.6,
        #            we had to make this take an explictly-created
        #            lambda Proc as a formal parameter.
        #
        # ====Returns
        #
        # The newly set value.
        #
        # ====Raises Exceptions
        #
        # Will raise an exception if the specified key is not already set
        # and non-nil.
        #
        # ====Examples
        #
        #     class Player < ActiveRecord::Base
        #       stashed_hash :stash
        #
        #       ...
        #
        #       # Record more more RBI for this player.
        #       def record_baseball_rbi
        #         self.stash.modify_data(
        #           'sports/baseball/stats/RBIs',
        #           lambda do |v|
        #             v + 1
        #           end
        #         )
        #       end
        #     end
        #
        define_method("modify_#{col_name}".to_sym) do |key, func|
          value = self.send("get_#{col_name}", key)
          if value
            self.send("set_#{col_name}", key, func.call(value))
          else
            raise "#{key.inspect} must be set before if can be modified"
          end
        end

        # Increments the value stored in the stashed hash under the
        # given +key+, and immediately saves this change to the database.
        #
        # NOTE: The specified key MUST already exist in order to increment it.
        #       When it does not already exist set_stash should be used first
        #       to set an initial value.
        #
        # REVISIT: This is built on top of modify_stash and the same
        #          REVISIT about safety applies.
        #
        # ====Parameters
        #
        # +key+::
        #   The key of the hash member to increment. This should be a String,
        #   and may be delimited into sections with forward-slashes, sort of
        #   like a file path. When slashes are preset, this key is treated
        #   as a nested hash key. For example, a key specified as:
        #
        #     "sports/baseball/stats/RBIs"
        #
        #   will actually increment the value of:
        #
        #     obj.stash['sports']['baseball']['stats']['RBIs']
        #
        # +delta+::
        #   An optional delta number to increment the value by. If unspecified
        #   this defaults to 1. This may be negative to decrement the
        #   the value.
        #
        # ====Returns
        #
        # The newly set value.
        #
        # ====Raises Exceptions
        #
        # Will raise an exception if the specified key is not already set
        # and non-nil.
        #
        define_method("inc_#{col_name}".to_sym) do |key, *optional_delta|
          if optional_delta.size > 1
            raise ArgumentError, "wrong number of arguments (#{optional_delta.size + 1} for 2)"
          end
          self.send(
            "modify_#{col_name}",
            key,
            lambda{|v| v + (optional_delta.first || 1)}
          )
        end
      end
    end
  end

  # REVISIT: These ought to be optimized to be iterative, not need
  #          to keep splitting/joining the keys, and not need to
  #          actually extend the Hash class. This is just a shortcut for now.
  module HashExtensions
    def stash_nested_get(key)
      keys      = key.to_s.strip.split('/')
      first_key = keys.shift
      if keys.empty?
        self[first_key]
      elsif self[first_key]
        self[first_key].stash_nested_get(keys.join('/'))
      else
        nil
      end
    end

    def stash_nested_delete(key)
      keys = key.to_s.strip.split('/')
      first_key = keys.shift
      if keys.empty?
        self.delete(first_key)
      else
        self[first_key].stash_nested_delete(keys.join('/'))
      end
    end

    def stash_nested_set(key, value)
      keys      = key.to_s.strip.split('/')
      first_key = keys.shift
      if keys.empty?
        self[first_key] = value
      else
        (self[first_key] || (self[first_key] = {})).stash_nested_set(keys.join('/'), value)
      end
    end
  end
end

ActiveRecord::Base.class_eval{include StashedHash}
Hash.class_eval{include StashedHash::HashExtensions}
