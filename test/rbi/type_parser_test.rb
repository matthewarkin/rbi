# typed: true
# frozen_string_literal: true

require "test_helper"

module RBI
  class TypeParserTest < Minitest::Test
    def test_parse_empty
      assert_raises(RBI::Type::Parser::Error) do
        Type::Parser.parse("")
      end
    end

    def test_parse_simple
      type = Type::Parser.parse("Foo")
      assert_equal("Foo", type.to_s)

      type = Type::Parser.parse("Foo::Bar")
      assert_equal("Foo::Bar", type.to_s)

      type = Type::Parser.parse("::Foo::Bar")
      assert_equal("::Foo::Bar", type.to_s)
    end

    def test_parse_boolean
      type = Type::Parser.parse("T::Boolean")
      assert_equal(Type.boolean, type)

      type = Type::Parser.parse("::T::Boolean")
      assert_equal(Type.boolean, type)
    end

    def test_parse_anything
      type = Type::Parser.parse("T.anything")
      assert_equal(Type.anything, type)

      type = Type::Parser.parse("::T.anything")
      assert_equal(Type.anything, type)
    end

    def test_parse_void
      type = Type::Parser.parse("void")
      assert_equal(Type.void, type)
    end

    def test_parse_untyped
      type = Type::Parser.parse("T.untyped")
      assert_equal(Type.untyped, type)
    end

    def test_parse_self_type
      type = Type::Parser.parse("T.self_type")
      assert_equal(Type.self_type, type)
    end

    def test_parse_attached_class
      type = Type::Parser.parse("T.attached_class")
      assert_equal(Type.attached_class, type)
    end

    def test_parse_nilable
      type = Type::Parser.parse("T.nilable(Foo)")
      assert_equal(Type.nilable(Type.simple("Foo")), type)

      type = Type::Parser.parse("T.nilable(Foo::Bar)")
      assert_equal(Type.nilable(Type.simple("Foo::Bar")), type)

      type = Type::Parser.parse("T.nilable(::Foo::Bar)")
      assert_equal(Type.nilable(Type.simple("::Foo::Bar")), type)
    end

    def test_parse_class_of
      e = assert_raises(RBI::Type::Parser::Error) do
        Type::Parser.parse("T.class_of")
      end
      assert_equal("Expected exactly 1 argument, got 0", e.message)

      e = assert_raises(RBI::Type::Parser::Error) do
        Type::Parser.parse("T.class_of(Foo, Bar)")
      end
      assert_equal("Expected exactly 1 argument, got 2", e.message)

      type = Type::Parser.parse("T.class_of(Foo)")
      assert_equal(Type.class_of(Type.simple("Foo")), type)

      type = Type::Parser.parse("T.class_of(Foo::Bar)")
      assert_equal(Type.class_of(Type.simple("Foo::Bar")), type)

      type = Type::Parser.parse("T.class_of(::Foo::Bar)")
      assert_equal(Type.class_of(Type.simple("::Foo::Bar")), type)
    end

    def test_parse_all
      e = assert_raises(RBI::Type::Parser::Error) do
        Type::Parser.parse("T.all(Foo)")
      end
      assert_equal("Expected at least 2 arguments, got 1", e.message)

      type = Type::Parser.parse("T.all(Foo, Bar)")
      assert_equal(
        Type.all(
          Type.simple("Foo"),
          Type.simple("Bar"),
        ),
        type,
      )

      type = Type::Parser.parse("T.all(Foo, ::Bar, ::Foo::Bar)")
      assert_equal(
        Type.all(
          Type.simple("Foo"),
          Type.simple("::Bar"),
          Type.simple("::Foo::Bar"),
        ),
        type,
      )
    end

    def test_parse_any
      e = assert_raises(RBI::Type::Parser::Error) do
        Type::Parser.parse("T.any(Foo)")
      end
      assert_equal("Expected at least 2 arguments, got 1", e.message)

      type = Type::Parser.parse("T.any(Foo, Bar)")
      assert_equal(
        Type.any(
          Type.simple("Foo"),
          Type.simple("Bar"),
        ),
        type,
      )

      type = Type::Parser.parse("T.any(Foo, ::Bar, ::Foo::Bar)")
      assert_equal(
        Type.any(
          Type.simple("Foo"),
          Type.simple("::Bar"),
          Type.simple("::Foo::Bar"),
        ),
        type,
      )
    end

    def test_parse_generic
      e = assert_raises(RBI::Type::Parser::Error) do
        Type::Parser.parse("Foo[]")
      end
      assert_equal("Expected at least 1 argument, got 0", e.message)

      type = Type::Parser.parse("Foo[Bar]")
      assert_equal(
        Type.generic(
          "Foo",
          Type.simple("Bar"),
        ),
        type,
      )

      type = Type::Parser.parse("::Foo::Bar[::Baz, ::Foo::Bar]")
      assert_equal(
        Type.generic(
          "::Foo::Bar",
          Type.simple("::Baz"),
          Type.simple("::Foo::Bar"),
        ),
        type,
      )
    end

    def test_parse_tuple
      type = Type::Parser.parse("[Foo, ::Bar::Baz]")
      assert_equal(
        Type.tuple(
          Type.simple("Foo"),
          Type.simple("::Bar::Baz"),
        ),
        type,
      )
    end

    def test_parse_shape
      type = Type::Parser.parse("{foo: Foo, bar: ::Bar::Baz}")
      assert_equal(
        Type.shape(
          foo: Type.simple("Foo"),
          bar: Type.simple("::Bar::Baz"),
        ),
        type,
      )
    end

    def test_parse_proc
      type = Type::Parser.parse("T.proc.void")
      assert_equal(Type.proc.void, type)

      type = Type::Parser.parse("T.proc.returns(Integer)")
      assert_equal(
        Type.proc.returns(
          Type.simple("Integer"),
        ),
        type,
      )

      type = Type::Parser.parse("T.proc.params(foo: Foo).returns(Baz)")
      assert_equal(
        Type.proc.params(
          foo: Type.simple("Foo"),
        ).returns(
          Type.simple("Baz"),
        ),
        type,
      )
    end

    def test_parse_complex_type
      type = Type::Parser.parse(<<~RBI)
        T.proc.params(
          foo: [{foo: Foo, bar: Bar}, T::Boolean],
          bar: T.nilable(T.class_of(Baz)),
          baz: T.all(T.any(Foo, Bar), T::Boolean)
        ).returns(
          Foo[Bar, T.nilable(Baz)]
        )
      RBI
      assert_equal(
        Type.proc.params(
          foo: Type.tuple(
            Type.shape(
              foo: Type.simple("Foo"),
              bar: Type.simple("Bar"),
            ),
            Type.boolean,
          ),
          bar: Type.nilable(Type.class_of(Type.simple("Baz"))),
          baz: Type.all(
            Type.any(
              Type.simple("Foo"),
              Type.simple("Bar"),
            ),
            Type.boolean,
          ),
        ).returns(
          Type.generic(
            "Foo",
            Type.simple("Bar"),
            Type.nilable(Type.simple("Baz")),
          ),
        ),
        type,
      )
    end
  end
end
