# typed: true
# frozen_string_literal: true

class Foo
  sig { params(x: String, y: T.nilable(Integer)).returns(T.nilable(String)) }
  def foo(x, y: nil); end
end
