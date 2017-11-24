module ActiveRecord
  module NamedScope
    module ClassMethods

      def scoping(&block)
        scoped(&block)
      end

      def named_scope(name, options = {}, &block)
        name = name.to_sym

        scopes[name] = lambda do |parent_scope, *args|
          Scope.new(parent_scope, case options
            when Hash, Scope
              options
            when Proc
              options.call(*args)
          end, &block)
        end

        singleton_class.send :define_method, name do |*args|
          scopes[name].call(self, *args)
        end
      end

      # make all arguments optional, like Rails 3
      def scoped(scope = {}, &block)
        ActiveRecord::NamedScope::Scope.new(self, scope, &block)
      end
    end

    class Scope
      undef from

      def select(value = Proc.new)
        if block_given?
          all.select {|*block_args| value.call(*block_args) }
        else
          self.scoped(:select => Array.wrap(value).join(','))
        end
      end

      alias initialize_without_arel initialize
      def initialize(proxy_scope, options = {}, &block)
        options = options.unspin if options.class == ActiveRecord::NamedScope::Scope
        initialize_without_arel(proxy_scope, options, &block)
      end

      def unspin
        # unspin the scope and generate a hash
        local_scope = proxy_scope
        ret = proxy_options
        while local_scope.class == ActiveRecord::NamedScope::Scope
          ret[:select] = local_scope.proxy_options[:select] unless local_scope.proxy_options[:select].nil?
          local_conditions = merge_conditions(local_scope.proxy_options[:conditions])
          if local_conditions && ret[:conditions]
            if (ret[:conditions].class == Hash and !ret[:conditions].keys.include?(local_conditions)) or (ret[:conditions].class != Hash and !ret[:conditions].index(local_conditions))
              ret[:conditions] = merge_conditions(ret[:conditions], local_scope.proxy_options[:conditions])
            end
          elsif local_conditions
            ret[:conditions] = local_conditions
          end
          ret[:include] = merge_includes(ret[:include], local_scope.proxy_options[:include])
          if ret[:joins] || local_scope.proxy_options[:joins]
            # this is a bit ugly, but I was getting error with using OR.
            begin
              ret[:joins] = merge_joins(ret[:joins], local_scope.proxy_options[:joins])
            rescue ActiveRecord::ConfigurationError
              ret[:joins] = merge_joins((ret[:joins] || []), (local_scope.proxy_options[:joins] || []))
            end
          end

          local_proxy_order_options = local_scope.proxy_options[:order].split(',') unless local_scope.proxy_options[:order].nil?
          ret_order_options = ret[:order].split(',') unless ret[:order].nil?
          ret[:order] = [local_proxy_order_options, ret_order_options].flatten.uniq.select{|o| !o.blank?}.join(',') if ret[:order] || local_scope.proxy_options[:order]
          local_scope = local_scope.proxy_scope
        end
        ret
      end
    end

  end
end
