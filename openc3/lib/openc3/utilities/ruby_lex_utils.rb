# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'irb'
require 'irb/ruby-lex'
require 'stringio'

# Clear the $VERBOSE global since we're overriding methods
old_verbose = $VERBOSE; $VERBOSE = nil
class RubyLex
  attr_accessor :indent
  attr_accessor :line_no
  attr_accessor :exp_line_no
  attr_accessor :tokens
  attr_accessor :code_block_open
  attr_accessor :ltype
  attr_accessor :line
  attr_accessor :continue

  def reinitialize
    @line_no = 1
    @prompt = nil
    initialize_input()
  end

  major, minor, _ = RUBY_VERSION.split('.')
  if major == '3' and minor.to_i < 2
    alias orig_lex lex
    def lex(context)
      orig_lex()
    end
  end
end
$VERBOSE = old_verbose

class RubyLexUtils
  # Regular expression to detect blank lines
  BLANK_LINE_REGEX  = /^\s*$/
  # Regular expression to detect lines containing only 'else'
  LONELY_ELSE_REGEX = /^\s*else\s*$/

  KEY_KEYWORDS = [
    'class'.freeze,
    'module'.freeze,
    'def'.freeze,
    'undef'.freeze,
    'begin'.freeze,
    'rescue'.freeze,
    'ensure'.freeze,
    'end'.freeze,
    'if'.freeze,
    'unless'.freeze,
    'then'.freeze,
    'elsif'.freeze,
    'else'.freeze,
    'case'.freeze,
    'when'.freeze,
    'while'.freeze,
    'until'.freeze,
    'for'.freeze,
    'break'.freeze,
    'next'.freeze,
    'redo'.freeze,
    'retry'.freeze,
    'in'.freeze,
    'do'.freeze,
    'return'.freeze,
    'alias'.freeze
  ]

  # Create a new RubyLex and StringIO to hold the text to operate on
  def initialize
    # Taken from https://github.com/ruby/ruby/blob/master/test/irb/test_ruby_lex.rb#L827
    IRB.init_config(nil)
    IRB.conf[:VERBOSE] = false
    # IRB.setup doesn't work because the command line options are passed
    # and it doesn't recognize --warnings when we run rspec (see spec.rake)
    # IRB.setup(__FILE__)
    workspace = IRB::WorkSpace.new(binding)
    @context = IRB::Context.new(nil, workspace)

    @lex    = RubyLex.new
    @lex_io = StringIO.new('')
  end

  def ripper_lex_without_warning(code)
    RubyLex.ripper_lex_without_warning(code)
  end

  # @param text [String]
  # @return [Boolean] Whether the text contains the 'begin' keyword
  def contains_begin?(text)
    @lex.reinitialize
    @lex_io.string = text
    @lex.set_input(@lex_io, context: @context)
    tokens = ripper_lex_without_warning(text)
    tokens.each do |token|
      if token[1] == :on_kw and token[2] == 'begin'
        return true
      end
    end
    return false
  end

  # @param text [String]
  # @return [Boolean] Whether the text contains the 'end' keyword
  def contains_end?(text)
    @lex.reinitialize
    @lex_io.string = text
    @lex.set_input(@lex_io, context: @context)
    tokens = ripper_lex_without_warning(text)
    tokens.each do |token|
      if token[1] == :on_kw and token[2] == 'end'
        return true
      end
    end
    return false
  end

  # @param text [String]
  # @return [Boolean] Whether the text contains a Ruby keyword
  def contains_keyword?(text)
    @lex.reinitialize
    @lex_io.string = text
    @lex.set_input(@lex_io, context: @context)
    tokens = ripper_lex_without_warning(text)
    tokens.each do |token|
      if token[1] == :on_kw
        if KEY_KEYWORDS.include?(token[2])
          return true
        end
      elsif token[1] == :on_lbrace and !token[3].allbits?(Ripper::EXPR_BEG | Ripper::EXPR_LABEL)
        return true
      end
    end
    return false
  end

  # @param text [String]
  # @return [Boolean] Whether the text contains a keyword which starts a block.
  #   i.e. 'do', '{', or 'begin'
  def contains_block_beginning?(text)
    @lex.reinitialize
    @lex_io.string = text
    @lex.set_input(@lex_io, context: @context)
    tokens = ripper_lex_without_warning(text)
    tokens.each do |token|
      if token[1] == :on_kw
        if token[2] == 'begin' || token[2] == 'do'
          return true
        end
      elsif token[1] == :on_lbrace
        return true
      end
    end
    return false
  end

  def continue_block?(text)
    @lex.reinitialize
    @lex_io.string = text
    @lex.set_input(@lex_io, context: @context)
    tokens = RubyLex.ripper_lex_without_warning(text)
    index = tokens.length - 1
    while index > 0
      token = tokens[index]
      return true if token[1] == :on_kw and token[2] == "do"
      index -= 1
    end
    return false
  end

  # @param text [String]
  # @param progress_dialog [OpenC3::ProgressDialog] If this is set, the overall
  #   progress will be set as the processing progresses
  # @return [String] The text with all comments removed
  def remove_comments(text, progress_dialog = nil)
    @lex.reinitialize
    @lex_io.string = text
    @lex.set_input(@lex_io, context: @context)
    comments_removed = ""
    token_count = 0
    progress = 0.0
    tokens = ripper_lex_without_warning(text)
    tokens.each do |token|
      token_count += 1
      if token[1] != :on_comment
        comments_removed << token[2]
      else
        newline_count = token[2].count("\n")
        comments_removed << ("\n" * newline_count)
      end
      if progress_dialog and token_count % 10000 == 0
        progress += 0.01
        progress = 0.0 if progress >= 0.99
        progress_dialog.set_overall_progress(progress)
      end
    end

    return comments_removed
  end

  # Yields each lexed segment and if the segment is instrumentable
  #
  # @param text [String]
  # @yieldparam line [String] The entire line
  # @yieldparam instrumentable [Boolean] Whether the line is instrumentable
  # @yieldparam inside_begin [Integer] The level of indentation
  # @yieldparam line_no [Integer] The current line number
  def each_lexed_segment(text)
    inside_begin = false
    lex = RubyLex.new
    lex_io = StringIO.new(text)
    lex.set_input(lex_io, context: @context)
    lex.line = ''
    line = ''
    indent = 0
    continue_indent = nil
    begin_indent = nil
    previous_line_indent = 0

    while lexed = lex.lex(@context)
      lex.line_no += lexed.count("\n")
      lex.line.concat lexed
      line.concat lexed

      if continue_indent
        indent = previous_line_indent + lex.indent
      else
        indent += lex.indent
        lex.indent = 0
      end

      if inside_begin and indent < begin_indent
        begin_indent = nil
        inside_begin = false
      end

      # Uncomment the following to help with debugging
      #puts
      #puts '*' * 80
      #puts lex.line
      #puts "lexed = #{lexed.chomp}, indent (of next line) = #{indent}, actual lex.indent = #{lex.indent}, continue = #{lex.continue}, ltype = #{lex.ltype.inspect}, code_block_open = #{lex.code_block_open}, continue_indent = #{continue_indent.inspect}, begin_indent = #{begin_indent.inspect}"

      # These lines put multiple lines together that are really one line
      if lex.continue or lex.ltype
        if not continue_block?(lexed)
          # Set the indent we should stop at
          unless continue_indent
            if (indent - previous_line_indent) > 1
              continue_indent = indent - 1
            else
              continue_indent = previous_line_indent
            end
          end
          next
        end
      elsif continue_indent
        if indent > continue_indent
          # Still have more content
          next
        else
          # Ready to yield this combined line
          yield line, !contains_keyword?(line), inside_begin, lex.exp_line_no
          line = ''
          lex.exp_line_no = lex.line_no
          lex.line = ''
          next
        end
      end
      previous_line_indent = indent
      continue_indent = nil

      # Detect the beginning and end of begin blocks so we can not catch exceptions there
      if contains_begin?(line)
        if contains_end?(line)
          # Assume the user is being fancy with a single line begin; end;
          # Ignore
        else
          inside_begin = true
          begin_indent = indent unless begin_indent # Don't restart for nested begins
        end
      end

      # The following code does not care about indent

      loop do # loop to allow restarting for nested conditions
        # Yield blank lines and lonely else lines before the actual line
        while (index = line.index("\n"))
          one_line = line[0..index]
          if BLANK_LINE_REGEX.match?(one_line)
            yield one_line, true, inside_begin, lex.exp_line_no
            lex.exp_line_no += 1
            line = line[(index + 1)..-1]
          elsif LONELY_ELSE_REGEX.match?(one_line)
            yield one_line, false, inside_begin, lex.exp_line_no
            lex.exp_line_no += 1
            line = line[(index + 1)..-1]
          else
            break
          end
        end

        if contains_keyword?(line)
          yield line, false, inside_begin, lex.exp_line_no
        elsif !line.empty?
          yield line, true, inside_begin, lex.exp_line_no
        end
        line = ''
        lex.exp_line_no = lex.line_no
        lex.line = ''
        break
      end # loop do
    end # while lexed
  end # def each_lexed_segment
end
