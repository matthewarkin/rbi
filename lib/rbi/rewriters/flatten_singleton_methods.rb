# typed: strict
# frozen_string_literal: true

module RBI
  module Rewriters
    class FlattenSingletonMethods < Visitor
      # @override
      #: (Node? node) -> void
      def visit(node)
        return unless node

        case node
        when SingletonClass
          node.nodes.dup.each do |child|
            visit(child)
            next unless child.is_a?(Method) && !child.is_singleton

            child.detach
            child.is_singleton = true
            parent_tree = node.parent_tree #:: Tree
            parent_tree << child
          end

          node.detach
        when Tree
          visit_all(node.nodes)
        end
      end
    end
  end

  class Tree
    #: -> void
    def flatten_singleton_methods!
      visitor = Rewriters::FlattenSingletonMethods.new
      visitor.visit(self)
    end
  end
end
