# typed: true
# frozen_string_literal: true

require "test_helper"

module RBI
  class RBSPrinterTest < Minitest::Test
    def test_print_files_without_strictness
      file = File.new
      file.root << Module.new("Foo")

      assert_equal(<<~RBI, file.rbs_string)
        module Foo
        end
      RBI
    end

    def test_print_files_with_strictness_but_omit_it
      file = File.new(strictness: "true")
      file.root << Module.new("Foo")

      assert_equal(<<~RBI, file.rbs_string)
        module Foo
        end
      RBI
    end

    def test_print_modules_and_classes
      rbi = Tree.new
      rbi << Module.new("Foo")
      rbi << Class.new("Bar")
      rbi << Class.new("Baz", superclass_name: "Bar")
      rbi << SingletonClass.new

      assert_equal(<<~RBI, rbi.rbs_string)
        module Foo
        end

        class Bar
        end

        class Baz < Bar
        end

        class << self
        end
      RBI
    end

    def test_print_nested_scopes
      scope1 = Module.new("Foo")
      scope2 = Class.new("Bar")
      scope3 = Class.new("Baz", superclass_name: "Bar")
      scope4 = SingletonClass.new

      rbi = Tree.new
      rbi << scope1
      scope1 << scope2
      scope2 << scope3
      scope3 << scope4

      assert_equal(<<~RBI, rbi.rbs_string)
        module Foo
          class Bar
            class Baz < Bar
              class << self
              end
            end
          end
        end
      RBI
    end

    def test_print_structs
      rbi = Tree.new do |tree|
        tree << Struct.new("Foo", members: [:foo, :bar])
        tree << Struct.new("Bar", members: [:bar], keyword_init: true) do |struct1|
          struct1 << Method.new("bar_method")
        end
        tree << Struct.new("Baz", members: [:baz], keyword_init: false) do |struct2|
          struct2 << Method.new("baz_method")
          struct2 << SingletonClass.new do |singleton_class|
            singleton_class << Method.new("baz_class_method")
          end
        end
      end

      assert_equal(<<~RBI, rbi.rbs_string)
        Foo = ::Struct.new(:foo, :bar)

        Bar = ::Struct.new(:bar, keyword_init: true) do
          def bar_method
        end

        Baz = ::Struct.new(:baz) do
          def baz_method

          class << self
            def baz_class_method
          end
        end
      RBI
    end

    def test_print_constants
      rbi = Tree.new
      rbi << Const.new("Foo", "42")
      rbi << Const.new("Bar", "'foo'")
      rbi << Const.new("Baz", "Bar")

      assert_equal(<<~RBI, rbi.rbs_string)
        Foo = 42
        Bar = 'foo'
        Baz = Bar
      RBI
    end

    def test_print_attributes
      rbi = Tree.new
      rbi << AttrReader.new(:m1)
      rbi << AttrWriter.new(:m2, :m3, visibility: Private.new)
      rbi << AttrAccessor.new(:m4, visibility: Public.new)
      rbi << AttrReader.new(:m5, visibility: Protected.new)

      assert_equal(<<~RBI, rbi.rbs_string)
        attr_reader m1
        private attr_writer m2
        private attr_writer m3
        attr_accessor m4
        protected attr_reader m5
      RBI
    end

    def test_print_methods
      rbi = Tree.new
      rbi << Method.new("m1")
      rbi << Method.new("m2", visibility: Public.new)
      rbi << Method.new("m3", visibility: Private.new)
      rbi << Method.new("m4", visibility: Protected.new)
      rbi << Method.new("m5", is_singleton: true)
      rbi << Method.new("m6", is_singleton: true, visibility: Private.new) # TODO: avoid this?

      assert_equal(<<~RBI, rbi.rbs_string)
        def m1
        def m2
        private def m3
        protected def m4
        def self.m5
        private def self.m6
      RBI
    end

    def test_print_methods_with_parameters
      method = Method.new("foo")
      method << ReqParam.new("a")
      method << OptParam.new("b", "42")
      method << RestParam.new("c")
      method << KwParam.new("d")
      method << KwOptParam.new("e", "'bar'")
      method << KwRestParam.new("f")
      method << BlockParam.new("g")

      assert_equal(<<~RBI, method.rbs_string)
        def foo(a, b = 42, *c, d:, e: 'bar', **f, &g)
      RBI
    end

    def test_print_attributes_with_signatures
      sig1 = Sig.new(return_type: "Integer")

      sig2 = Sig.new(return_type: "R")
      sig2 << SigParam.new("a", "A")
      sig2 << SigParam.new("b", "T.nilable(B)")
      sig2 << SigParam.new("b", "T.proc.void")

      sig3 = Sig.new(is_abstract: true)
      sig3.is_override = true
      sig3.is_overridable = true

      sig4 = Sig.new(return_type: "T.type_parameter(:V)")
      sig4.type_params << "U"
      sig4.type_params << "V"
      sig4 << SigParam.new("a", "T.type_parameter(:U)")

      attr = AttrAccessor.new(:foo, :bar)
      attr.sigs << sig1
      attr.sigs << sig2
      attr.sigs << sig3
      attr.sigs << sig4

      assert_equal(<<~RBI, attr.rbs_string)
        attr_accessor foo: Integer
        attr_accessor bar: Integer
      RBI
    end

    def test_print_methods_with_signatures_simple
      sig = Sig.new(return_type: "R")
      sig << SigParam.new("a", "A")
      sig << SigParam.new("b", "T.nilable(B)")
      sig << SigParam.new("block", "T.proc.void")

      method = Method.new("foo") do |node|
        node.sigs << sig
        node.params << ReqParam.new("a")
        node.params << OptParam.new("b", "42")
        node.params << BlockParam.new("block")
      end

      assert_equal(<<~RBI, method.rbs_string)
        def foo: (A, B?) { -> void } -> R
      RBI
    end

    def test_print_methods_with_signatures
      sig1 = Sig.new

      sig2 = Sig.new(return_type: "R")
      sig2 << SigParam.new("a", "A")
      sig2 << SigParam.new("b", "T.nilable(B)")
      sig2 << SigParam.new("b", "T.proc.void")

      sig3 = Sig.new(is_abstract: true)
      sig3.is_override = true
      sig3.is_overridable = true
      sig3.checked = :never

      sig4 = Sig.new(return_type: "T.type_parameter(:V)")
      sig4.type_params << "U"
      sig4.type_params << "V"
      sig4 << SigParam.new("a", "T.type_parameter(:U)")

      method = Method.new("foo")
      method.sigs << sig1
      method.sigs << sig2
      method.sigs << sig3
      method.sigs << sig4

      assert_equal(<<~RBI, method.rbs_string)
        def foo: -> void
               | (a: A, b: T.nilable(B), b: T.proc.void) -> R
               | -> void
               | [U, V] (a: U) -> V
      RBI
    end

    def test_print_mixins
      scope = Class.new("Foo")
      scope << Include.new("A")
      scope << Extend.new("A", "B")

      assert_equal(<<~RBI, scope.rbs_string)
        class Foo
          include A
          extend A, B
        end
      RBI
    end

    def test_print_visibility_labels
      tree = Tree.new
      tree << Public.new
      tree << Method.new("m1")
      tree << Protected.new
      tree << Method.new("m2")
      tree << Private.new
      tree << Method.new("m3")

      assert_equal(<<~RBI, tree.rbs_string)
        public
        def m1
        protected
        def m2
        private
        def m3
      RBI
    end

    def test_print_sends
      tree = Tree.new
      tree << Send.new("class_attribute")
      tree << Send.new("class_attribute") do |send|
        send << Arg.new(":foo")
      end
      tree << Send.new("class_attribute") do |send|
        send << Arg.new(":foo")
        send << Arg.new(":bar")
        send << KwArg.new("instance_accessor", "false")
        send << KwArg.new("default", "\"Bar\"")
      end

      assert_equal(<<~RBI, tree.rbs_string)
        class_attribute
        class_attribute :foo
        class_attribute :foo, :bar, instance_accessor: false, default: "Bar"
      RBI
    end

    def test_print_t_structs
      struct = TStruct.new("Foo")
      struct << TStructConst.new("a", "A")
      struct << TStructConst.new("b", "B", default: "B.new")
      struct << TStructProp.new("c", "C")
      struct << TStructProp.new("d", "D", default: "D.new")
      struct << Method.new("foo")

      assert_equal(<<~RBI, struct.rbs_string)
        class Foo < ::T::Struct
          const :a, A
          const :b, B, default: B.new
          prop :c, C
          prop :d, D, default: D.new
          def foo
        end
      RBI
    end

    def test_print_t_enums
      rbi = TEnum.new("Foo")
      block = TEnumBlock.new(["A", "B"])
      block.names << "C"
      rbi << block
      rbi << Method.new("baz")

      assert_equal(<<~RBI, rbi.rbs_string)
        class Foo < ::T::Enum
          enums do
            A = new
            B = new
            C = new
          end
          def baz
        end
      RBI
    end

    def test_print_sorbet_helpers
      rbi = Class.new("Foo")
      rbi << Helper.new("foo")
      rbi << Helper.new("sealed")
      rbi << Helper.new("interface")
      rbi << MixesInClassMethods.new("A")
      rbi << RequiresAncestor.new("A")

      assert_equal(<<~RBI, rbi.rbs_string)
        class Foo
          foo!
          sealed!
          interface!
          mixes_in_class_methods A
          requires_ancestor { A }
        end
      RBI
    end

    def test_print_sorbet_type_members_and_templates
      rbi = Class.new("Foo")
      rbi << TypeMember.new("A", "type_member")
      rbi << TypeMember.new("B", "type_template")

      assert_equal(<<~RBI, rbi.rbs_string)
        class Foo
          A = type_member
          B = type_template
        end
      RBI
    end

    def test_print_files_with_comments_but_no_strictness
      comments = [
        Comment.new("This is a"),
        Comment.new("Multiline Comment"),
      ]

      file = File.new(comments: comments)
      file.root << Module.new("Foo")

      assert_equal(<<~RBI, file.rbs_string)
        # This is a
        # Multiline Comment

        module Foo
        end
      RBI
    end

    def test_print_with_comments_and_strictness
      comments = [
        Comment.new("This is a"),
        Comment.new("Multiline Comment"),
      ]

      file = File.new(strictness: "true", comments: comments)
      file.root << Module.new("Foo")

      assert_equal(<<~RBI, file.rbs_string)
        # This is a
        # Multiline Comment

        module Foo
        end
      RBI
    end

    def test_print_nodes_with_comments
      comments_single = [Comment.new("This is a single line comment")]

      comments_multi = [
        Comment.new("This is a"),
        Comment.new("Multiline Comment"),
      ]

      rbi = Tree.new
      rbi << Module.new("Foo", comments: comments_single)
      rbi << Class.new("Bar", comments: comments_multi)
      rbi << SingletonClass.new(comments: comments_single)
      rbi << Const.new("Foo", "42", comments: comments_multi)
      rbi << Include.new("A", comments: comments_single)
      rbi << Extend.new("A", comments: comments_multi)

      rbi << Public.new(comments: comments_single)
      rbi << Protected.new(comments: comments_single)
      rbi << Private.new(comments: comments_single)

      rbi << Send.new("foo", comments: comments_single)

      struct = TStruct.new("Foo", comments: comments_single)
      struct << TStructConst.new("a", "A", comments: comments_multi)
      struct << TStructProp.new("c", "C", comments: comments_single)
      rbi << struct

      enum = TEnum.new("Foo", comments: comments_multi)
      enum << TEnumBlock.new(["A", "B"], comments: comments_single)
      rbi << enum

      rbi << Helper.new("foo", comments: comments_multi)
      rbi << MixesInClassMethods.new("A", comments: comments_single)
      rbi << TypeMember.new("A", "type_member", comments: comments_multi)
      rbi << TypeMember.new("B", "type_template", comments: comments_single)

      assert_equal(<<~RBI, rbi.rbs_string)
        # This is a single line comment
        module Foo
        end

        # This is a
        # Multiline Comment
        class Bar
        end

        # This is a single line comment
        class << self
        end

        # This is a
        # Multiline Comment
        Foo = 42

        # This is a single line comment
        include A

        # This is a
        # Multiline Comment
        extend A

        # This is a single line comment
        public

        # This is a single line comment
        protected

        # This is a single line comment
        private

        # This is a single line comment
        foo

        # This is a single line comment
        class Foo < ::T::Struct
          # This is a
          # Multiline Comment
          const :a, A

          # This is a single line comment
          prop :c, C
        end

        # This is a
        # Multiline Comment
        class Foo < ::T::Enum
          # This is a single line comment
          enums do
            A = new
            B = new
          end
        end

        # This is a
        # Multiline Comment
        foo!

        # This is a single line comment
        mixes_in_class_methods A

        # This is a
        # Multiline Comment
        A = type_member

        # This is a single line comment
        B = type_template
      RBI
    end

    def test_print_nodes_with_multiline_comments
      comments = [Comment.new("This is a\nmultiline\n  comment")]

      rbi = Tree.new do |tree|
        tree << Module.new("Foo", comments: comments) do |mod|
          mod << TypeMember.new("A", "type_member", comments: comments)
          mod << Method.new("foo", comments: comments)
        end
      end

      rbi << Method.new("foo", comments: comments) do |method|
        method << ReqParam.new("a", comments: comments)
        method << OptParam.new("b", "42", comments: comments)
        method << RestParam.new("c", comments: comments)
        method << KwParam.new("d", comments: comments)
        method << KwOptParam.new("e", "'bar'", comments: comments)
        method << KwRestParam.new("f", comments: comments)
        method << BlockParam.new("g", comments: comments)

        sig = Sig.new
        sig << SigParam.new("a", "Integer", comments: comments)
        sig << SigParam.new("b", "String", comments: comments)
        sig << SigParam.new("c", "T.untyped", comments: comments)
        method.sigs << sig
      end

      assert_equal(<<~RBI, rbi.rbs_string)
        # This is a
        # multiline
        #   comment
        module Foo
          # This is a
          # multiline
          #   comment
          A = type_member

          # This is a
          # multiline
          #   comment
          def foo
        end

        # This is a
        # multiline
        #   comment
        def foo(
          a, # This is a
             # multiline
             #   comment
          b = 42, # This is a
                  # multiline
                  #   comment
          *c, # This is a
              # multiline
              #   comment
          d:, # This is a
              # multiline
              #   comment
          e: 'bar', # This is a
                    # multiline
                    #   comment
          **f, # This is a
               # multiline
               #   comment
          &g # This is a
             # multiline
             #   comment
        ): (
          a: Integer, # This is a
                      # multiline
                      #   comment
          b: String, # This is a
                     # multiline
                     #   comment
          c: T.untyped # This is a
                       # multiline
                       #   comment
        ) -> void
      RBI
    end

    def test_print_nodes_with_heredoc_comments
      comments = [Comment.new(<<~COMMENT)]
        This
        is
        a
        multiline
        comment
      COMMENT

      rbi = Tree.new do |tree|
        tree << Module.new("Foo", comments: comments)
      end

      assert_equal(<<~RBI, rbi.rbs_string)
        # This
        # is
        # a
        # multiline
        # comment
        module Foo
        end
      RBI
    end

    def test_print_methods_with_signatures_and_comments
      comments_single = [Comment.new("This is a single line comment")]

      comments_multi = [
        Comment.new("This is a"),
        Comment.new("Multiline Comment"),
      ]

      rbi = Tree.new
      rbi << Method.new("foo", comments: comments_multi)

      method = Method.new("foo", comments: comments_single)
      method.sigs << Sig.new
      rbi << method

      sig1 = Sig.new
      sig2 = Sig.new(return_type: "R")
      sig2 << SigParam.new("a", "A")
      sig2 << SigParam.new("b", "T.nilable(B)")
      sig2 << SigParam.new("b", "T.proc.void")

      method = Method.new("bar", comments: comments_multi)
      method.sigs << sig1
      method.sigs << sig2
      rbi << method

      assert_equal(<<~RBI, rbi.rbs_string)
        # This is a
        # Multiline Comment
        def foo

        # This is a single line comment
        def foo: -> void

        # This is a
        # Multiline Comment
        def bar: -> void
               | (a: A, b: T.nilable(B), b: T.proc.void) -> R
      RBI
    end

    def test_print_tree_header_comments
      rbi = Tree.new(comments: [
        Comment.new("typed: true"),
        Comment.new("frozen_string_literal: false"),
      ])
      rbi << Module.new("Foo", comments: [Comment.new("Foo comment")])

      assert_equal(<<~RBI, rbi.rbs_string)
        # typed: true
        # frozen_string_literal: false

        # Foo comment
        module Foo
        end
      RBI
    end

    def test_print_empty_comments
      tree = Tree.new(comments: [
        Comment.new("typed: true"),
        Comment.new(""),
        Comment.new("Some intro comment"),
        Comment.new("Some other comment"),
      ])

      assert_equal(<<~RBI, tree.rbs_string)
        # typed: true
        #
        # Some intro comment
        # Some other comment
      RBI
    end

    def test_print_empty_trees_with_comments
      rbi = File.new(strictness: "true")
      rbi.root.comments << Comment.new("foo")

      assert_equal(<<~RBI, rbi.rbs_string)
        # foo
      RBI
    end

    def test_print_params_inline_comments
      comments = [Comment.new("comment")]

      method = Method.new("foo", comments: comments)
      method << ReqParam.new("a", comments: comments)
      method << OptParam.new("b", "42", comments: comments)
      method << RestParam.new("c", comments: comments)
      method << KwParam.new("d", comments: comments)
      method << KwOptParam.new("e", "'bar'", comments: comments)
      method << KwRestParam.new("f", comments: comments)
      method << BlockParam.new("g", comments: comments)

      assert_equal(<<~RBI, method.rbs_string)
        # comment
        def foo(
          a, # comment
          b = 42, # comment
          *c, # comment
          d:, # comment
          e: 'bar', # comment
          **f, # comment
          &g # comment
        )
      RBI
    end

    def test_print_params_multiline_comments
      comments = [
        Comment.new("comment 1"),
        Comment.new("comment 2"),
      ]

      method = Method.new("foo", comments: comments)
      method << ReqParam.new("a", comments: comments)
      method << OptParam.new("b", "42", comments: comments)
      method << RestParam.new("c", comments: comments)
      method << KwParam.new("d", comments: comments)
      method << KwOptParam.new("e", "'bar'", comments: comments)
      method << KwRestParam.new("f", comments: comments)
      method << BlockParam.new("g", comments: comments)

      assert_equal(<<~RBI, method.rbs_string)
        # comment 1
        # comment 2
        def foo(
          a, # comment 1
             # comment 2
          b = 42, # comment 1
                  # comment 2
          *c, # comment 1
              # comment 2
          d:, # comment 1
              # comment 2
          e: 'bar', # comment 1
                    # comment 2
          **f, # comment 1
               # comment 2
          &g # comment 1
             # comment 2
        )
      RBI
    end

    def test_print_sig_params_inline_comments
      comments = [Comment.new("comment")]

      sig = Sig.new
      sig << SigParam.new("a", "Integer", comments: comments)
      sig << SigParam.new("b", "String", comments: comments)
      sig << SigParam.new("c", "T.untyped", comments: comments)

      assert_equal(<<~RBI.strip, sig.rbs_string)
        (
          a: Integer, # comment
          b: String, # comment
          c: T.untyped # comment
        ) -> void
      RBI
    end

    def test_print_sig_params_multiline_comments
      comments = [
        Comment.new("comment 1"),
        Comment.new("comment 2"),
      ]

      sig = Sig.new
      sig << SigParam.new("a", "Integer", comments: comments)
      sig << SigParam.new("b", "String", comments: comments)
      sig << SigParam.new("c", "T.untyped", comments: comments)

      assert_equal(<<~RBI.strip, sig.rbs_string)
        (
          a: Integer, # comment 1
                      # comment 2
          b: String, # comment 1
                     # comment 2
          c: T.untyped # comment 1
                       # comment 2
        ) -> void
      RBI
    end

    def test_print_sig_params_multiline_comments_with_modifiers
      comments = [
        Comment.new("comment 1"),
        Comment.new("comment 2"),
      ]

      sig = Sig.new(is_abstract: true, is_override: true, is_overridable: true, checked: :always, return_type: "A")
      sig.type_params << "TP1"
      sig.type_params << "TP2"
      sig << SigParam.new("a", "Integer", comments: comments)
      sig << SigParam.new("b", "String", comments: comments)
      sig << SigParam.new("c", "T.untyped", comments: comments)

      assert_equal(<<~RBI.strip, sig.rbs_string)
        [TP1, TP2] (
          a: Integer, # comment 1
                      # comment 2
          b: String, # comment 1
                     # comment 2
          c: T.untyped # comment 1
                       # comment 2
        ) -> A
      RBI
    end

    def test_print_sig_under_max_line_length
      rbi = Tree.new do |tree|
        tree << Class.new("Foo") do |cls|
          cls << Sig.new(is_abstract: true, is_overridable: true) do |sig|
            sig << SigParam.new("a", "Integer")
            sig << SigParam.new("b", "String")
            sig << SigParam.new("c", "T.untyped")
          end
          cls << Method.new("foo") do |method|
            method << ReqParam.new("a")
            method << ReqParam.new("b")
            method << ReqParam.new("c")
          end
        end
      end

      assert_equal(<<~RBI, rbi.rbs_string(max_line_length: 80))
        class Foo
          sig { abstract.overridable.params(a: Integer, b: String, c: T.untyped).void }
          def foo(a, b, c)
        end
      RBI
    end

    def test_print_sig_over_max_line_length
      rbi = File.new do |file|
        file << Class.new("Foo") do |cls|
          cls << Method.new("foo") do |method|
            method << ReqParam.new("a")
            method << ReqParam.new("b")
            method << ReqParam.new("c")
            method.sigs << Sig.new(is_abstract: true, is_overridable: true) do |sig|
              sig << SigParam.new("a", "Integer")
              sig << SigParam.new("b", "Integer")
              sig << SigParam.new("c", "T.untyped")
            end
          end
        end
      end

      assert_equal(<<~RBI, rbi.rbs_string(max_line_length: 80))
        class Foo
          def foo(a, b, c): (
            a: Integer,
            b: Integer,
            c: T.untyped
          ) -> void
        end
      RBI
    end

    def test_print_sig_over_max_line_length_with_all_modifiers
      sig = Sig.new
      assert_equal("-> void", sig.rbs_string(max_line_length: 1))

      sig = Sig.new(is_abstract: true)
      assert_equal("-> void", sig.rbs_string(max_line_length: 1))

      sig = Sig.new(is_override: true)
      assert_equal("-> void", sig.rbs_string(max_line_length: 1))

      sig = Sig.new(is_abstract: true, is_override: true)

      assert_equal("-> void", sig.rbs_string(max_line_length: 1))

      sig = Sig.new
      sig << SigParam.new("a", "Integer")

      assert_equal(<<~RBI.strip, sig.rbs_string(max_line_length: 1))
        (
          a: Integer
        ) -> void
      RBI

      sig = Sig.new(is_overridable: true)
      sig << SigParam.new("a", "Integer")

      assert_equal(<<~RBI.strip, sig.rbs_string(max_line_length: 1))
        (
          a: Integer
        ) -> void
      RBI

      sig = Sig.new(checked: :never)
      sig << SigParam.new("a", "Integer")

      assert_equal(<<~RBI.strip, sig.rbs_string(max_line_length: 1))
        (
          a: Integer
        ) -> void
      RBI

      sig = Sig.new(type_params: ["A", "B", "C"])

      assert_equal(<<~RBI.strip, sig.rbs_string(max_line_length: 1))
        [A, B, C] -> void
      RBI
    end

    def test_print_blank_lines
      comments = [
        Comment.new("comment 1"),
        BlankLine.new,
        Comment.new("comment 2"),
      ]

      rbi = Module.new("Foo", comments: comments) do |mod|
        mod << BlankLine.new
        mod << Method.new("foo")
        mod << BlankLine.new
        mod << BlankLine.new
        mod << BlankLine.new

        mod << Class.new("Bar") do |cls|
          cls << Comment.new("begin")
          cls << BlankLine.new
          cls << BlankLine.new
          cls << Comment.new("middle")
          cls << BlankLine.new
          cls << BlankLine.new
          cls << Comment.new("end")
        end
      end

      assert_equal(<<~RBI, rbi.rbs_string)
        # comment 1

        # comment 2
        module Foo

          def foo



          class Bar
            # begin


            # middle


            # end
          end
        end
      RBI
    end

    def test_print_new_lines_between_scopes
      rbi = Tree.new
      scope = Class.new("Bar")
      scope << Include.new("ModuleA")
      rbi << scope
      rbi << Module.new("ModuleA")

      rbi.group_nodes!
      rbi.sort_nodes!

      assert_equal(<<~RBI, rbi.rbs_string)
        class Bar
          include ModuleA
        end

        module ModuleA
        end
      RBI
    end

    def test_print_new_lines_between_methods_with_sigs
      rbi = Tree.new
      rbi << Method.new("m1")
      rbi << Method.new("m2")

      m3 = Method.new("m3")
      m3.sigs << Sig.new
      rbi << m3

      rbi << Method.new("m4")

      m5 = Method.new("m5")
      m5.sigs << Sig.new
      m5.sigs << Sig.new
      rbi << m5

      m6 = Method.new("m6")
      m6.sigs << Sig.new
      rbi << m6

      rbi << Method.new("m7")
      rbi << Method.new("m8")

      rbi.group_nodes!
      rbi.sort_nodes!

      assert_equal(<<~RBI, rbi.rbs_string)
        def m1
        def m2

        def m3: -> void

        def m4

        def m5: -> void
              | -> void

        def m6: -> void

        def m7
        def m8
      RBI
    end

    def test_print_nodes_locations
      loc = Loc.new(file: "file.rbi", begin_line: 1, end_line: 2, begin_column: 3, end_column: 4)

      rbi = Tree.new(loc: loc)
      rbi << Module.new("S1", loc: loc)
      rbi << Class.new("S2", loc: loc)
      rbi << SingletonClass.new(loc: loc)
      rbi << TEnum.new("TE", loc: loc)
      rbi << TStruct.new("TS", loc: loc)
      rbi << Const.new("C", "42", loc: loc)
      rbi << Extend.new("E", loc: loc)
      rbi << Include.new("I", loc: loc)
      rbi << Send.new("foo", loc: loc)
      rbi << MixesInClassMethods.new("MICM", loc: loc)
      rbi << Helper.new("abstract", loc: loc)
      rbi << TStructConst.new("SC", "Type", loc: loc)
      rbi << TStructProp.new("SP", "Type", loc: loc)
      rbi << Method.new("m1", loc: loc)

      assert_equal(<<~RBI, rbi.rbs_string(print_locs: true))
        # file.rbi:1:3-2:4
        module S1
        end

        # file.rbi:1:3-2:4
        class S2
        end

        # file.rbi:1:3-2:4
        class << self
        end

        # file.rbi:1:3-2:4
        class TE < ::T::Enum
        end

        # file.rbi:1:3-2:4
        class TS < ::T::Struct
        end

        # file.rbi:1:3-2:4
        C = 42
        # file.rbi:1:3-2:4
        extend E
        # file.rbi:1:3-2:4
        include I
        # file.rbi:1:3-2:4
        foo
        # file.rbi:1:3-2:4
        mixes_in_class_methods MICM
        # file.rbi:1:3-2:4
        abstract!
        # file.rbi:1:3-2:4
        const :SC, Type
        # file.rbi:1:3-2:4
        prop :SP, Type
        # file.rbi:1:3-2:4
        def m1
      RBI
    end

    def test_print_sigs_locations
      loc = Loc.new(file: "file.rbi", begin_line: 1, end_line: 2, begin_column: 3, end_column: 4)

      sig1 = Sig.new(loc: loc)
      sig2 = Sig.new(loc: loc)

      rbi = Tree.new(loc: loc)
      rbi << Method.new("m1", sigs: [sig1, sig2], loc: loc)

      assert_equal(<<~RBI, rbi.rbs_string(print_locs: true))
        # file.rbi:1:3-2:4
        def m1: -> void # file.rbi:1:3-2:4
              | -> void # file.rbi:1:3-2:4
      RBI
    end
  end
end
