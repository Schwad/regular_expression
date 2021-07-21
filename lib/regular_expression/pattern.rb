# frozen_string_literal: true

module RegularExpression
  class Pattern
    attr_reader :bytecode

    def initialize(source, flags = "")
      flags = Flags.parse(flags)
      ast = Parser.new.parse(source)
      @bytecode = Bytecode.compile(ast.to_nfa(flags))
    end

    def compile(compiler: Compiler::X86)
      cfg = CFG.build(bytecode)
      schedule = Scheduler.schedule(cfg)

      singleton_class.undef_method(:match?)
      define_singleton_method(:match?, &compiler.compile(cfg, schedule))
    end

    def match?(string)
      Interpreter.new(bytecode).match?(string)
    end
  end
end
