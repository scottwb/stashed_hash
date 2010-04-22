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
    #                 an empty Hash.
    #
    def stashed_hash(col_name, options = {})
      configuration = {
        :initial => {}
      }
      configuration.update(options) if options.is_a?(Hash)
        
      col_spec = self.columns.find{|c| c.name.to_s == col_name.to_s}
      if col_spec.nil?
        raise "#{col_name.inspect} is not a valid column for #{self.name}"
      end
      if col_spec.type != :text
        raise "#{col_name.inspect} is not a :text column"
      end

      class_eval do
        serialize col_name, Hash
        before_create do |obj|
          if obj.send(col_name).nil?
            obj.send("#{col_name}=", configuration[:initial])
          end
          true
        end
      end
    end
  end

end

ActiveRecord::Base.class_eval{include StashedHash}
