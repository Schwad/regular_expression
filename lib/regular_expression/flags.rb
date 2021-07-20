# frozen_string_literal: true

module RegularExpression
  class Flags
    ALL = ["i"].freeze

    def initialize(flags)
      @flags = Set.new(flags.chars)

      unknowns = @flags - ALL
      raise ArgumentError, "Unkown flag: #{unknowns.first}" if unknowns.any?
    end

    def i?
      @flags.include?("i")
    end

    def self.empty
      NO_FLAGS
    end

    NO_FLAGS = Flags.new("").freeze
    def self.parse(string)
      return NO_FLAGS if string.nil? || string.empty?

      Flags.new(string)
    end
  end
end
