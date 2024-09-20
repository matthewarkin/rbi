# typed: strict
# frozen_string_literal: true

module RBI
  module Rewriters
    class FlattenSingletonMethods < Visitor
      extend T::Sig

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
            T.must(node.parent_tree) << child
          end

          node.detach
        when Tree
          visit_all(node.nodes)
        end
      end
    end
  end

  class Tree
    extend T::Sig

    #: -> void
    def flatten_singleton_methods!
      visitor = Rewriters::FlattenSingletonMethods.new
      visitor.visit(self)
    end
  end
end
