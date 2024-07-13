# typed: strict
# frozen_string_literal: true

module RBI
  class Type
    class Parser < Prism::Visitor
      extend T::Sig
      extend T::Helpers

      class Error < RBI::Error; end

      class << self
        extend T::Sig

        sig { params(string: String).returns(Type) }
        def parse(string)
          result = Prism.parse(string)
          unless result.success?
            message = result.errors.map { |e| "#{e.message}." }.join(" ")
            error = result.errors.first
            location = Loc.new(
              file: "-",
              begin_line: error.location.start_line,
              begin_column: error.location.start_column,
            )
            raise ParseError.new(message, location)
          end

          node = result.value
          raise Error, "Failed to parse type" unless node.is_a?(Prism::ProgramNode)

          node = node.statements.body.first
          raise Error, "Expected a node" unless node

          parse_node(node)
        end

        private

        sig { params(node: Prism::Node).returns(Type) }
        def parse_node(node)
          case node
          when Prism::ConstantReadNode, Prism::ConstantPathNode
            parse_constant(node)
          when Prism::CallNode
            parse_call(node)
          when Prism::ArrayNode
            parse_tuple(node)
          when Prism::HashNode
            parse_shape(node)
          else
            raise Error, "Unknown node #{node}"
          end
        end

        sig { params(node: T.any(Prism::ConstantReadNode, Prism::ConstantPathNode)).returns(Type) }
        def parse_constant(node)
          case node
          when Prism::ConstantReadNode
            Type.simple(node.slice)
          when Prism::ConstantPathNode
            const = node.slice

            case const
            when "T::Boolean", "::T::Boolean"
              Type.boolean
            else
              Type.simple(const)
            end
          end
        end

        sig { params(node: Prism::CallNode).returns(Type) }
        def parse_call(node)
          recv = node.receiver

          case node.name
          when :void
            return Type.void if recv.nil?
          when :[]
            case recv
            when Prism::ConstantReadNode, Prism::ConstantPathNode
              args = check_arguments_at_least!(node, 1)
              return T.unsafe(Type).generic(recv.slice, *args.map { |arg| parse_node(arg) })
            else
              raise
            end
          end

          case recv
          when Prism::ConstantReadNode, Prism::ConstantPathNode
            const = recv.slice
            case const
            when "T", "::T"
              # OK
            else
              raise Error, "Unknown constant #{recv.slice}"
            end
          else
            if recv && node.slice.start_with?("T.proc")
              return parse_proc(node)
            end

            raise Error, "Unknown receiver #{recv}"
          end

          case node.name
          when :nilable
            args = check_arguments_count!(node, 1)
            type = parse_node(T.must(args.first))
            Type.nilable(type)
          when :anything
            check_arguments_count!(node, 0)
            Type.anything
          when :untyped
            check_arguments_count!(node, 0)
            Type.untyped
          when :self_type
            check_arguments_count!(node, 0)
            Type.self_type
          when :attached_class
            check_arguments_count!(node, 0)
            Type.attached_class
          when :class_of
            args = check_arguments_count!(node, 1)
            type = parse_node(T.must(args.first))
            raise Error, "Expected simple type" unless type.is_a?(Type::Simple)

            Type.class_of(type)
          when :all
            args = check_arguments_at_least!(node, 2)
            T.unsafe(Type).all(*args.map { |arg| parse_node(arg) })
          when :any
            args = check_arguments_at_least!(node, 2)
            T.unsafe(Type).any(*args.map { |arg| parse_node(arg) })
          else
            raise Error, "Unknown method #{node.name}"
          end
        end

        sig { params(node: Prism::ArrayNode).returns(Type) }
        def parse_tuple(node)
          T.unsafe(Type).tuple(*node.elements.map { |elem| parse_node(elem) })
        end

        sig { params(node: Prism::HashNode).returns(Type) }
        def parse_shape(node)
          hash = node.elements.map do |elem|
            raise Error, "Expected key-value pair" unless elem.is_a?(Prism::AssocNode)

            [elem.key.slice.delete_suffix(":").to_sym, parse_node(elem.value)]
          end.to_h
          T.unsafe(Type).shape(**hash)
        end

        sig { params(node: Prism::CallNode).returns(Type) }
        def parse_proc(node)
          calls = []

          call = T.let(node, T.nilable(Prism::Node))
          while call
            break unless call.is_a?(Prism::CallNode)

            calls << call
            call = call.receiver
          end

          type = Type.proc
          calls.each do |call|
            case call.name
            when :params
              args = call.arguments&.arguments || []
              hash = args.first
              raise Error, "Expected hash, got #{hash.class}" unless hash.is_a?(Prism::KeywordHashNode)

              params = hash.elements.map do |elem|
                raise Error, "Expected key-value pair" unless elem.is_a?(Prism::AssocNode)

                [elem.key.slice.delete_suffix(":").to_sym, parse_node(elem.value)]
              end.to_h
              T.unsafe(type).params(**params)
            when :returns
              args = check_arguments_count!(call, 1)
              type.returns(parse_node(T.must(args.first)))
            when :void
              type.void
            when :proc
              return type
            else
              raise Error, "Unknown method #{call.name}"
            end
          end
          type
        end

        sig { params(node: Prism::CallNode, count: Integer).returns(T::Array[Prism::Node]) }
        def check_arguments_count!(node, count)
          args = node.arguments&.arguments || []
          unless args.size == count
            if count == 0
              raise Error, "Expected no arguments, got #{args.size}"
            elsif count == 1
              raise Error, "Expected exactly 1 argument, got #{args.size}"
            else
              raise Error, "Expected exactly #{count} arguments, got #{args.size}"
            end
          end
          args
        end

        sig { params(node: Prism::CallNode, count: Integer).returns(T::Array[Prism::Node]) }
        def check_arguments_at_least!(node, count)
          args = node.arguments&.arguments || []
          if args.size < count
            if count == 1
              raise Error, "Expected at least 1 argument, got #{args.size}"
            else
              raise Error, "Expected at least #{count} arguments, got #{args.size}"
            end
          end
          args
        end
      end
    end
  end
end
