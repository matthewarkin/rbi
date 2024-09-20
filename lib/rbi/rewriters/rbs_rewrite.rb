# typed: strict
# frozen_string_literal: true

module RBI
  module Rewriters
    class RBSRewrite < Visitor
      extend T::Sig

      # @override
      #: (Node? node) -> void
      def visit(node)
        return unless node

        case node
        when Tree
          visit_all(node.nodes)
        when Method
          scope = node.parent_scope
          unless scope
            parent = node.parent_tree
            raise unless parent

            node.detach
            parent.nodes << Class.new("Object") do |klass|
              klass << node
            end
          end
        end
      end
    end
  end

  class Tree
    extend T::Sig

    #: -> void
    def rbs_rewrite!
      visitor = Rewriters::RBSRewrite.new
      visitor.visit(self)
    end
  end
end
