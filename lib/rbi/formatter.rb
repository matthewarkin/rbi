# typed: strict
# frozen_string_literal: true

module RBI
  class Formatter
    #: bool
    attr_writer :sort_nodes

    #: Integer?
    attr_accessor :max_line_length

    #: (?add_sig_templates: bool, ?group_nodes: bool, ?max_line_length: Integer?, ?nest_singleton_methods: bool, ?nest_non_public_methods: bool, ?sort_nodes: bool) -> void
    def initialize(
      add_sig_templates: false,
      group_nodes: false,
      max_line_length: nil,
      nest_singleton_methods: false,
      nest_non_public_methods: false,
      sort_nodes: false
    )
      @add_sig_templates = add_sig_templates
      @group_nodes = group_nodes
      @max_line_length = max_line_length
      @nest_singleton_methods = nest_singleton_methods
      @nest_non_public_methods = nest_non_public_methods
      @sort_nodes = sort_nodes
    end

    #: (RBI::File file) -> String
    def print_file(file)
      format_file(file)
      file.string(max_line_length: @max_line_length)
    end

    #: (RBI::File file) -> void
    def format_file(file)
      format_tree(file.root)
    end

    #: (RBI::Tree tree) -> void
    def format_tree(tree)
      tree.add_sig_templates! if @add_sig_templates
      tree.nest_singleton_methods! if @nest_singleton_methods
      tree.nest_non_public_methods! if @nest_non_public_methods
      tree.group_nodes! if @group_nodes
      tree.sort_nodes! if @sort_nodes
    end
  end
end
