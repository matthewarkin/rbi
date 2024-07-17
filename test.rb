# typed: strict
# frozen_string_literal: true

class Foo
  # @param x -- some docs
  def foo(x, y: nil)
    x + y
  end
end
