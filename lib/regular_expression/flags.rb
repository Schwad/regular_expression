# frozen_string_literal: true

module RegularExpression
  module Flags
    class InsensitiveFlag
      class << self
        def modify_state(start)
          # Not using `#each` so that added transitions aren't picked up again,
          # which would result in an infinite loop
          start.transitions.size.times do |i|
            transition = start.transitions[i]

            case transition
            when NFA::Transition::Range
              new_left = other_value_case(transition.left) || transition.left
              new_right = other_value_case(transition.right) || transition.right

              next if transition.left <= new_left && transition.right >= new_right

              new_transition = NFA::Transition::Range.new(transition.state, new_left, new_right)
              start.add_transition(new_transition)
            when NFA::Transition::Value
              next unless (new_value = other_value_case(transition.value))

              start.add_transition(NFA::Transition::Value.new(transition.state, new_value))
            end
          end
        end

        private

        def other_value_case(char)
          if char != (downcase = char.downcase)
            downcase
          elsif char != (upcase = char.upcase)
            upcase
          end
        end
      end
    end

    NAME_MAPPING = {
      "i" => InsensitiveFlag
    }.freeze

    def self.fetch(name)
      NAME_MAPPING.fetch(name) do
        raise ArgumentError, "Unknown flag: #{name}"
      end
    end

    NO_FLAGS = [].freeze
    private_constant(:NO_FLAGS)

    def self.parse(string)
      return NO_FLAGS if string.nil? || string.empty?

      string.each_char.map { |char| fetch(char) }
    end
  end
end
