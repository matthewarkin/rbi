# typed: strict
# frozen_string_literal: true

module RBI
  module Validators
    class Values < Visitor
      extend T::Sig

      class Error < Validators::Error; end

      sig { returns(T::Array[Error]) }
      attr_reader :errors

      sig { void }
      def initialize
        @errors = T.let([], T::Array[Error])
      end

      sig { override.params(node: T.nilable(Node)).void }
      def visit(node)
        return unless node

        case node
        when SigParam
          validate_type(node, node.type)
        when Sig
          visit_all(node.params)
          return_type = node.return_type
          validate_type(node, return_type) if return_type
        when Method, Attr
          visit_all(node.sigs)
        when TStructField
          validate_type(node, node.type)
        end

        visit_all(node.nodes) if node.is_a?(Tree)
      end

      private

      sig { params(node: Node, type: String).void }
      def validate_type(node, type)
        node_kind = node.class.to_s.sub("RBI::", "")
        case type
        when //

        when /T.nilable(CONST)/
        when /T.nilable(CONST)/
        when /CONST/
        else
          errors << Error.new("invalid type `#{type}` for #{node_kind}", node: node)
        end
      end
    end
  end
end
