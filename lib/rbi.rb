# typed: strict
# frozen_string_literal: true

require "stringio"

module RBI
  class Error < StandardError
  end
end

require "rbi/loc"
require "rbi/model"
require "rbi/type"
require "rbi/visitor"
require "rbi/index"
require "rbi/rewriters/add_sig_templates"
require "rbi/rewriters/annotate"
require "rbi/rewriters/deannotate"
require "rbi/rewriters/filter_versions"
require "rbi/rewriters/flatten_singleton_methods"
require "rbi/rewriters/inline_visibilities"
require "rbi/rewriters/merge_trees"
require "rbi/rewriters/nest_singleton_methods"
require "rbi/rewriters/nest_non_public_methods"
require "rbi/rewriters/group_nodes"
require "rbi/rewriters/remove_known_definitions"
require "rbi/rewriters/attr_to_methods"
require "rbi/rewriters/sort_nodes"
require "rbi/rewriters/rbs_rewrite"
require "rbi/parser"
require "rbi/type_parser"
require "rbi/printer"
require "rbi/rbs_printer"
require "rbi/formatter"
require "rbi/version"
