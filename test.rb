# typed: strict
# frozen_string_literal: true

require "rbs"

RBS::Parser.parse_signature(<<~RBS)
  class Object
    def run: [T] (blk: ^(constant: ::Module, rbi: ::RBI::File) -> T) -> T
  end
RBS
