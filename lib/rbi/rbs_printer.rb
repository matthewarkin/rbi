# typed: strict
# frozen_string_literal: true

module RBI
  class RBSPrinter < Visitor
    extend T::Sig

    sig { returns(T::Boolean) }
    attr_accessor :print_locs, :in_visibility_group

    sig { returns(T.nilable(Node)) }
    attr_reader :previous_node

    sig { returns(Integer) }
    attr_reader :current_indent

    sig { returns(T.nilable(Integer)) }
    attr_reader :max_line_length

    sig do
      params(
        out: T.any(IO, StringIO),
        indent: Integer,
        print_locs: T::Boolean,
        max_line_length: T.nilable(Integer),
      ).void
    end
    def initialize(out: $stdout, indent: 0, print_locs: false, max_line_length: nil)
      super()
      @out = out
      @current_indent = indent
      @print_locs = print_locs
      @in_visibility_group = T.let(false, T::Boolean)
      @previous_node = T.let(nil, T.nilable(Node))
      @max_line_length = max_line_length
    end

    # Printing

    sig { void }
    def indent
      @current_indent += 2
    end

    sig { void }
    def dedent
      @current_indent -= 2
    end

    # Print a string without indentation nor `\n` at the end.
    sig { params(string: String).void }
    def print(string)
      @out.print(string)
    end

    # Print a string without indentation but with a `\n` at the end.
    sig { params(string: T.nilable(String)).void }
    def printn(string = nil)
      print(string) if string
      print("\n")
    end

    # Print a string with indentation but without a `\n` at the end.
    sig { params(string: T.nilable(String)).void }
    def printt(string = nil)
      print(" " * @current_indent)
      print(string) if string
    end

    # Print a string with indentation and `\n` at the end.
    sig { params(string: String).void }
    def printl(string)
      printt
      printn(string)
    end

    sig { override.params(nodes: T::Array[Node]).void }
    def visit_all(nodes)
      previous_node = @previous_node
      @previous_node = nil
      nodes.each do |node|
        visit(node)
        @previous_node = node
      end
      @previous_node = previous_node
    end

    sig { override.params(file: File).void }
    def visit_file(file)
      unless file.comments.empty?
        visit_all(file.comments)
      end

      unless file.root.empty? && file.root.comments.empty?
        printn unless file.comments.empty?
        visit(file.root)
      end
    end

    sig { override.params(node: Comment).void }
    def visit_comment(node)
      lines = node.text.lines

      if lines.empty?
        printl("#")
      end

      lines.each do |line|
        text = line.rstrip
        printt("#")
        print(" #{text}") unless text.empty?
        printn
      end
    end

    sig { override.params(node: BlankLine).void }
    def visit_blank_line(node)
      printn
    end

    sig { override.params(node: Tree).void }
    def visit_tree(node)
      visit_all(node.comments)
      printn if !node.comments.empty? && !node.empty?
      visit_all(node.nodes)
    end

    sig { override.params(node: Module).void }
    def visit_module(node)
      visit_scope(node)
    end

    sig { override.params(node: Class).void }
    def visit_class(node)
      visit_scope(node)
    end

    sig { override.params(node: Struct).void }
    def visit_struct(node)
      visit_scope(node)
    end

    sig { override.params(node: SingletonClass).void }
    def visit_singleton_class(node)
      visit_scope(node)
    end

    sig { params(node: Scope).void }
    def visit_scope(node)
      print_blank_line_before(node)
      print_loc(node)
      visit_all(node.comments)

      visit_scope_header(node)
      visit_scope_body(node)
    end

    sig { params(node: Scope).void }
    def visit_scope_header(node)
      case node
      when Module
        printt("module #{node.name}")
      when Class
        printt("class #{node.name}")
        superclass = node.superclass_name
        print(" < #{superclass}") if superclass
      when Struct
        printt("#{node.name} = ::Struct.new")
        if !node.members.empty? || node.keyword_init
          print("(")
          args = node.members.map { |member| ":#{member}" }
          args << "keyword_init: true" if node.keyword_init
          print(args.join(", "))
          print(")")
        end
      when SingletonClass
        printt("class << self")
      when TStruct
        printt("class #{node.name} < T::Struct")
      when TEnum
        printt("class #{node.name} < T::Enum")
      else
        raise PrinterError, "Unhandled node: #{node.class}"
      end
      if !node.empty? && node.is_a?(Struct)
        print(" do")
      end
      printn
    end

    sig { params(node: Scope).void }
    def visit_scope_body(node)
      unless node.empty?
        indent
        visit_all(node.nodes)
        dedent
      end
      if !node.is_a?(Struct) || !node.empty?
        printl("end")
      end
    end

    sig { override.params(node: Const).void }
    def visit_const(node)
      print_blank_line_before(node)
      print_loc(node)
      visit_all(node.comments)

      type = node.value.gsub(/T\.let\([^,]+, ?(.*)\)/, '\1')
      type = type_to_rbs(type)
      printl("#{node.name}: #{type}")
    end

    sig { override.params(node: AttrAccessor).void }
    def visit_attr_accessor(node)
      visit_attr(node)
    end

    sig { override.params(node: AttrReader).void }
    def visit_attr_reader(node)
      visit_attr(node)
    end

    sig { override.params(node: AttrWriter).void }
    def visit_attr_writer(node)
      visit_attr(node)
    end

    sig { params(node: Attr).void }
    def visit_attr(node)
      print_blank_line_before(node)

      node.names.each do |name|
        visit_all(node.comments)
        print_loc(node)
        printt
        unless in_visibility_group || node.visibility.public?
          self.print(node.visibility.visibility.to_s)
          print(" ")
        end
        case node
        when AttrAccessor
          print("attr_accessor")
        when AttrReader
          print("attr_reader")
        when AttrWriter
          print("attr_writer")
        end
        print(" #{name}")
        first_sig, *_rest = node.sigs # discard remaining signatures
        if first_sig
          type = type_to_rbs(first_sig.return_type.to_s)
          print(": #{type}")
        end
        printn
      end
    end

    sig { override.params(node: Method).void }
    def visit_method(node)
      print_blank_line_before(node)
      visit_all(node.comments)

      if node.sigs.any?(&:is_abstract)
        printl("# @abstract")
      end

      print_loc(node)
      printt
      unless in_visibility_group || node.visibility.public?
        self.print(node.visibility.visibility.to_s)
        print(" ")
      end
      print("def ")
      print("self.") if node.is_singleton
      print(node.name)
      sigs = node.sigs
      if sigs.any?
        print(": ")
        first, *rest = sigs
        print_method_sig(node, T.must(first))
        if rest.any?
          spaces = node.name.size + 4
          rest.each do |sig|
            printn
            printt
            print("#{" " * spaces}| ")
            print_method_sig(node, sig)
          end
        end
      else
        print(": (*untyped) -> untyped")
      end
      printn
    end

    sig { override.params(node: ReqParam).void }
    def visit_req_param(node)
      print(node.name)
    end

    sig { override.params(node: OptParam).void }
    def visit_opt_param(node)
      print("#{node.name} = #{node.value}")
    end

    sig { override.params(node: RestParam).void }
    def visit_rest_param(node)
      print("*#{node.name}")
    end

    sig { override.params(node: KwParam).void }
    def visit_kw_param(node)
      print("#{node.name}:")
    end

    sig { override.params(node: KwOptParam).void }
    def visit_kw_opt_param(node)
      print("#{node.name}: #{node.value}")
    end

    sig { override.params(node: KwRestParam).void }
    def visit_kw_rest_param(node)
      print("**#{node.name}")
    end

    sig { override.params(node: BlockParam).void }
    def visit_block_param(node)
      print("&#{node.name}")
    end

    sig { override.params(node: Include).void }
    def visit_include(node)
      visit_mixin(node)
    end

    sig { override.params(node: Extend).void }
    def visit_extend(node)
      visit_mixin(node)
    end

    sig { params(node: Mixin).void }
    def visit_mixin(node)
      return if node.is_a?(MixesInClassMethods) # no-op, `mixes_in_class_methods` is not supported in RBS

      print_blank_line_before(node)
      print_loc(node)
      visit_all(node.comments)

      case node
      when Include
        printt("include")
      when Extend
        printt("extend")
      end
      printn(" #{node.names.join(", ")}")
    end

    sig { override.params(node: Public).void }
    def visit_public(node)
      visit_visibility(node)
    end

    sig { override.params(node: Protected).void }
    def visit_protected(node)
      # no-op, `protected` is not supported in RBS
    end

    sig { override.params(node: Private).void }
    def visit_private(node)
      visit_visibility(node)
    end

    sig { params(node: Visibility).void }
    def visit_visibility(node)
      print_blank_line_before(node)
      print_loc(node)
      visit_all(node.comments)

      printl(node.visibility.to_s)
    end

    sig { override.params(node: Send).void }
    def visit_send(node)
      print_blank_line_before(node)
      print_loc(node)
      visit_all(node.comments)

      printt(node.method)
      unless node.args.empty?
        print(" ")
        node.args.each_with_index do |arg, index|
          visit(arg)
          print(", ") if index < node.args.size - 1
        end
      end
      printn
    end

    sig { override.params(node: Arg).void }
    def visit_arg(node)
      print(node.value)
    end

    sig { override.params(node: KwArg).void }
    def visit_kw_arg(node)
      print("#{node.keyword}: #{node.value}")
    end

    sig { params(node: RBI::Method, sig: Sig).void }
    def print_method_sig(node, sig)
      # max_line_length = self.max_line_length
      # if oneline?(node) && max_line_length.nil?
      print_sig_as_line(node, sig)
      # elsif max_line_length
      #   line = sig.string(indent: current_indent)
      #   if line.length <= max_line_length
      #     print(line)
      #   else
      #     print_sig_as_block(node, sig)
      #   end
      # else
      #   print_sig_as_block(node, sig)
      # end
    end

    sig { params(node: RBI::Attr, sig: Sig).void }
    def print_attr_sig(node, sig)
      type = type_to_rbs(sig.return_type.to_s)
      print(type)
    end

    sig { params(node: Method, param: SigParam).void }
    def print_sig_param(node, param)
      type = type_to_rbs(param.type.to_s)

      orig_param = node.params.find { |p| p.name == param.name }
      raise "Param not found: #{param.name}" unless orig_param

      case orig_param
      when ReqParam
        print("#{type} #{param.name}")
      when OptParam
        print("?#{type} #{param.name}")
      when RestParam
        print("*#{type} #{param.name}")
      when KwParam
        print("#{param.name}: #{type}")
      when KwOptParam
        print("?#{param.name}: #{type}")
      when KwRestParam
        print("**#{type} #{param.name}")
      else
        raise "Unexpected param type: #{orig_param.class}"
      end
    end

    sig { override.params(node: TStruct).void }
    def visit_tstruct(node)
      # no-op, `T::Struct` is not supported in RBS
    end

    sig { override.params(node: TStructConst).void }
    def visit_tstruct_const(node)
      # no-op, `T::Struct` is not supported in RBS
    end

    sig { override.params(node: TStructProp).void }
    def visit_tstruct_prop(node)
      # no-op, `T::Struct` is not supported in RBS
    end

    sig { override.params(node: TEnum).void }
    def visit_tenum(node)
      # no-op, `T::Enum` is not supported in RBS
    end

    sig { override.params(node: TEnumBlock).void }
    def visit_tenum_block(node)
      # no-op, `T::Enum` is not supported in RBS
    end

    sig { override.params(node: TypeMember).void }
    def visit_type_member(node)
      # TODO
    end

    sig { override.params(node: Helper).void }
    def visit_helper(node)
      # no-op, helpers such as `abstract!` or `interface!` are not supported in RBS
    end

    sig { override.params(node: MixesInClassMethods).void }
    def visit_mixes_in_class_methods(node)
      visit_mixin(node)
    end

    sig { override.params(node: Group).void }
    def visit_group(node)
      printn unless previous_node.nil?
      visit_all(node.nodes)
    end

    sig { override.params(node: VisibilityGroup).void }
    def visit_visibility_group(node)
      self.in_visibility_group = true
      if node.visibility.public?
        printn unless previous_node.nil?
      else
        visit(node.visibility)
        printn
      end
      visit_all(node.nodes)
      self.in_visibility_group = false
    end

    sig { override.params(node: RequiresAncestor).void }
    def visit_requires_ancestor(node)
      # no-op, `requires_ancestor` is not supported in RBS
    end

    sig { override.params(node: ConflictTree).void }
    def visit_conflict_tree(node)
      printl("<<<<<<< #{node.left_name}")
      visit(node.left)
      printl("=======")
      visit(node.right)
      printl(">>>>>>> #{node.right_name}")
    end

    sig { override.params(node: ScopeConflict).void }
    def visit_scope_conflict(node)
      print_blank_line_before(node)
      print_loc(node)
      visit_all(node.comments)

      printl("<<<<<<< #{node.left_name}")
      visit_scope_header(node.left)
      printl("=======")
      visit_scope_header(node.right)
      printl(">>>>>>> #{node.right_name}")
      visit_scope_body(node.left)
    end

    sig { params(node: Node).void }
    def print_blank_line_before(node)
      previous_node = self.previous_node
      return unless previous_node
      return if previous_node.is_a?(BlankLine)
      return if oneline?(previous_node) && oneline?(node)

      printn
    end

    sig { params(node: Node).void }
    def print_loc(node)
      loc = node.loc
      printl("# #{loc}") if loc && print_locs
    end

    sig { params(node: Param, last: T::Boolean).void }
    def print_param_comment_leading_space(node, last:)
      printn
      printt
      print(" " * (node.name.size + 1))
      print(" ") unless last
      case node
      when OptParam
        print(" " * (node.value.size + 3))
      when RestParam, KwParam, BlockParam
        print(" ")
      when KwRestParam
        print("  ")
      when KwOptParam
        print(" " * (node.value.size + 2))
      end
    end

    sig { params(node: SigParam, last: T::Boolean).void }
    def print_sig_param_comment_leading_space(node, last:)
      printn
      printt
      print(" " * (node.name.size + node.type.to_s.size + 3))
      print(" ") unless last
    end

    sig { params(node: Node).returns(T::Boolean) }
    def oneline?(node)
      case node
      when ScopeConflict
        oneline?(node.left)
      when Tree
        false
      when Attr
        node.comments.empty? && node.sigs.empty?
      when Method
        node.comments.empty? && node.sigs.empty? && node.params.all? { |p| p.comments.empty? }
      when Sig
        node.params.all? { |p| p.comments.empty? }
      when NodeWithComments
        node.comments.empty?
      when VisibilityGroup
        false
      else
        true
      end
    end

    sig { params(node: Method, sig: Sig).void }
    def print_sig_as_line(node, sig)
      unless sig.type_params.empty?
        print("[#{sig.type_params.map { |t| "TYPE_#{t}" }.join(", ")}] ")
      end

      block_param = node.params.find { |param| param.is_a?(BlockParam) }
      sig_block_param = sig.params.find { |param| param.name == block_param&.name }

      sig_params = sig.params
      if block_param
        sig_params.reject! do |param|
          param.name == block_param.name
        end
      end

      unless sig.params.empty?
        print("(")
        sig.params.each_with_index do |param, index|
          print(", ") if index > 0
          print_sig_param(node, param)
        end
        print(") ")
      end
      if sig_block_param
        block_type = sig_block_param.type
        is_nilable = false
        type = case block_type
        when String
          block_type = Type::Parser.parse(block_type)
          if block_type.is_a?(Type::Nilable)
            is_nilable = true
            block_type.type.rbs_string
          else
            block_type.rbs_string
          end
        when Type
          if block_type.is_a?(Type::Nilable)
            is_nilable = true
            block_type.type.rbs_string
          else
            block_type.rbs_string
          end
        end

        if is_nilable
          print("?{ #{type.delete_prefix("^")} } ")
        else
          print("{ #{type.delete_prefix("^")} } ")
        end
      end
      type = type_to_rbs(sig.return_type.to_s)
      print("-> #{type}")

      loc = sig.loc
      print(" # #{loc}") if loc && print_locs
    end

    sig { params(node: Method, sig: Sig).void }
    def print_sig_as_block(node, sig)
      unless sig.type_params.empty?
        print("[#{sig.type_params.map { |t| "TYPE_#{t}" }.join(", ")}] ")
      end

      params = sig.params
      if params.any?
        printn("(")
        indent
        params.each_with_index do |param, pindex|
          printt
          print_sig_param(node, param)
          print(",") if pindex < params.size - 1

          comment_lines = param.comments.flat_map { |comment| comment.text.lines.map(&:rstrip) }
          comment_lines.each_with_index do |comment, cindex|
            if cindex == 0
              print(" ")
            else
              print_sig_param_comment_leading_space(param, last: pindex == params.size - 1)
            end
            print("# #{comment}")
          end
          printn
        end
        dedent
        printt(") ")
      end
      printt if params.empty?

      return_type = type_to_rbs(sig.return_type.to_s)
      print("-> #{return_type}")
    end

    sig { params(type: String).returns(String) }
    def type_to_rbs(type)
      rbi_type = Type::Parser.parse(type)
      rbi_type.rbs_string
    rescue Type::Parser::Error => e
      # raise PrinterError, "Failed to parse type `#{type}` (#{e.message})"
      puts "Failed to parse type `#{type}` (#{e.message})"
      "untyped"
    end
  end

  class TypePrinter
    extend T::Sig

    sig { returns(String) }
    attr_reader :string

    sig { void }
    def initialize
      @string = T.let(String.new, String)
    end

    sig { params(node: Type).void }
    def visit(node)
      case node
      when Type::Simple
        visit_simple(node)
      when Type::Boolean
        visit_boolean(node)
      when Type::Verbatim
        visit_verbatim(node)
      when Type::Generic
        visit_generic(node)
      when Type::Anything
        visit_anything(node)
      when Type::Void
        visit_void(node)
      when Type::NoReturn
        visit_no_return(node)
      when Type::Untyped
        visit_untyped(node)
      when Type::SelfType
        visit_self_type(node)
      when Type::AttachedClass
        visit_attached_class(node)
      when Type::Nilable
        visit_nilable(node)
      when Type::ClassOf
        visit_class_of(node)
      when Type::All
        visit_all(node)
      when Type::Any
        visit_any(node)
      when Type::Tuple
        visit_tuple(node)
      when Type::Shape
        visit_shape(node)
      when Type::Proc
        visit_proc(node)
      when Type::TypeParameter
        visit_type_parameter(node)
      when Type::Class
        visit_class(node)
      else
        raise PrinterError, "Unhandled node: #{node.class}"
      end
    end

    sig { params(type: Type::Simple).void }
    def visit_simple(type)
      @string << type.name
    end

    sig { params(type: Type::Boolean).void }
    def visit_boolean(type)
      @string << "bool"
    end

    sig { params(type: Type::Verbatim).void }
    def visit_verbatim(type)
      @string << type.rbi_string
    end

    sig { params(type: Type::Generic).void }
    def visit_generic(type)
      @string << type.name
      @string << "["
      type.params.each_with_index do |arg, index|
        visit(arg)
        @string << ", " if index < type.params.size - 1
      end
      @string << "]"
    end

    sig { params(type: Type::Anything).void }
    def visit_anything(type)
      @string << "untyped" # TODO: bot
    end

    sig { params(type: Type::Void).void }
    def visit_void(type)
      @string << "void"
    end

    sig { params(type: Type::NoReturn).void }
    def visit_no_return(type)
      @string << "void"
    end

    sig { params(type: Type::Untyped).void }
    def visit_untyped(type)
      @string << "untyped"
    end

    sig { params(type: Type::SelfType).void }
    def visit_self_type(type)
      @string << "self"
    end

    sig { params(type: Type::AttachedClass).void }
    def visit_attached_class(type)
      @string << "attached_class"
    end

    sig { params(type: Type::Nilable).void }
    def visit_nilable(type)
      visit(type.type)
      @string << "?"
    end

    sig { params(type: Type::ClassOf).void }
    def visit_class_of(type)
      # @string << "singleton("
      # visit(type.type)
      # @string << ")"
      # TODO
      @string << "untyped"
    end

    sig { params(type: Type::All).void }
    def visit_all(type)
      @string << "("
      type.types.each_with_index do |arg, index|
        visit(arg)
        @string << " & " if index < type.types.size - 1
      end
      @string << ")"
    end

    sig { params(type: Type::Any).void }
    def visit_any(type)
      @string << "("
      type.types.each_with_index do |arg, index|
        visit(arg)
        @string << " | " if index < type.types.size - 1
      end
      @string << ")"
    end

    sig { params(type: Type::Tuple).void }
    def visit_tuple(type)
      @string << "["
      type.types.each_with_index do |arg, index|
        visit(arg)
        @string << ", " if index < type.types.size - 1
      end
      @string << "]"
    end

    sig { params(type: Type::Shape).void }
    def visit_shape(type)
      @string << "{"
      type.types.each_with_index do |(key, value), index|
        @string << "#{key}: "
        visit(value)
        @string << ", " if index < type.types.size - 1
      end
      @string << "}"
    end

    sig { params(type: Type::Proc).void }
    def visit_proc(type)
      @string << "^"
      if type.proc_params.any?
        @string << "("
        type.proc_params.each_with_index do |(key, value), index|
          @string << "#{key}: "
          visit(value)
          @string << ", " if index < type.proc_params.size - 1
        end
        @string << ") "
      end
      @string << "-> "
      visit(type.proc_returns)
    end

    sig { params(type: Type::TypeParameter).void }
    def visit_type_parameter(type)
      @string << "TYPE_#{type.name}"
    end

    sig { params(type: Type::Class).void }
    def visit_class(type)
      # @string << "singleton("
      # visit(type.type)
      # @string << ")"
      # TODO
      @string << "untyped"
    end
  end

  class File
    extend T::Sig

    sig do
      params(
        out: T.any(IO, StringIO),
        indent: Integer,
        print_locs: T::Boolean,
        max_line_length: T.nilable(Integer),
      ).void
    end
    def rbs_print(out: $stdout, indent: 0, print_locs: false, max_line_length: nil)
      p = RBSPrinter.new(out: out, indent: indent, print_locs: print_locs, max_line_length: max_line_length)
      p.visit_file(self)
    end

    sig { params(indent: Integer, print_locs: T::Boolean, max_line_length: T.nilable(Integer)).returns(String) }
    def rbs_string(indent: 0, print_locs: false, max_line_length: nil)
      out = StringIO.new
      rbs_print(out: out, indent: indent, print_locs: print_locs, max_line_length: max_line_length)
      out.string
    end
  end

  class Node
    extend T::Sig

    sig do
      params(
        out: T.any(IO, StringIO),
        indent: Integer,
        print_locs: T::Boolean,
        max_line_length: T.nilable(Integer),
      ).void
    end
    def rbs_print(out: $stdout, indent: 0, print_locs: false, max_line_length: nil)
      p = RBSPrinter.new(out: out, indent: indent, print_locs: print_locs, max_line_length: max_line_length)
      p.visit(self)
    end

    sig { params(indent: Integer, print_locs: T::Boolean, max_line_length: T.nilable(Integer)).returns(String) }
    def rbs_string(indent: 0, print_locs: false, max_line_length: nil)
      out = StringIO.new
      rbs_print(out: out, indent: indent, print_locs: print_locs, max_line_length: max_line_length)
      out.string
    end
  end

  class Type
    extend T::Sig

    sig { returns(String) }
    def rbs_string
      p = TypePrinter.new
      p.visit(self)
      p.string
    end
  end
end
