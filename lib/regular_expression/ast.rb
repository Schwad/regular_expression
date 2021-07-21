# frozen_string_literal: true

module RegularExpression
  module AST
    def self.to_dot(root)
      graph = Graphviz::Graph.new
      root.to_dot(graph)

      Graphviz.output(graph, path: "build/ast.svg", format: "svg")
      graph.to_dot
    end

    class Root
      attr_reader :expressions # Array[Expression]
      attr_reader :at_start # bool

      def initialize(expressions, at_start: false)
        @expressions = expressions
        @at_start = at_start
      end

      def to_dot(graph)
        label = "Root"
        label = "#{label} (at start)" if at_start

        node = graph.add_node(object_id, label: label)
        expressions.each { |expression| expression.to_dot(node) }
      end

      def to_nfa
        start_state = NFA::StartState.new
        match_start = NFA::State.new
        start_state.add_transition(NFA::Transition::StartCapture.new(match_start, "$0"))

        finish_state = NFA::FinishState.new
        match_finish = NFA::State.new
        match_finish.add_transition(NFA::Transition::EndCapture.new(finish_state, "$0"))

        current = match_start
        labels = ("1"..).each

        if at_start
          current = NFA::State.new(labels.next)
          match_start.add_transition(NFA::Transition::BeginAnchor.new(current))
        end

        worklist = expressions.reverse_each.map { |ex| [ex, current, match_finish] }

        while (node, start, finish = worklist.pop)
          case node
          when Expression
            items = node.items
            inner = Array.new(items.length - 1) { NFA::State.new(labels.next) }
            states = [start, *inner, finish]

            worklist += items.map.with_index do |item, index|
              [item, states[index], states[index + 1]]
            end.reverse!
          when Group
            expressions = node.expressions
            quantifier = node.quantifier

            worklist += apply_quantify(quantifier.quantify(start, finish, labels)) do |qstart, _qfinish, acc|
              expressions.each do |expression|
                acc << [expression, qstart, finish]
              end
            end

            worklist += work.reverse!
          when CaptureGroup
            expressions = node.expressions
            quantifier = node.quantifier
            name = node.name

            worklist += apply_quantify(quantifier.quantify(start, finish, labels)) do |qstart, qfinish, acc|
              capture_start = NFA::State.new
              qstart.add_transition(NFA::Transition::StartCapture.new(capture_start, name))

              capture_finish = NFA::State.new
              capture_finish.add_transition(NFA::Transition::EndCapture.new(qfinish, name))

              expressions.map do |expression|
                acc << [expression, capture_start, capture_finish]
              end
            end
          when Match
            item = node.item
            quantifier = node.quantifier

            worklist += apply_quantify(quantifier.quantify(start, finish, labels)) do |qstart, qfinish, acc|
              acc << [item, qstart, qfinish]
            end
          when CharacterGroup
            items = node.items

            if node.invert
              transition = NFA::Transition::Invert.new(finish, items.flat_map(&:to_nfa_values).sort)
              start.add_transition(transition)
            else
              worklist += items.map do |nitem|
                [nitem, start, finish]
              end.reverse!
            end
          when CharacterClass
            case node.value
            when %q{\w}
              start.add_transition(NFA::Transition::Range.new(finish, "a", "z"))
              start.add_transition(NFA::Transition::Range.new(finish, "A", "Z"))
              start.add_transition(NFA::Transition::Range.new(finish, "0", "9"))
              start.add_transition(NFA::Transition::Value.new(finish, "_"))
            when %q{\W}
              start.add_transition(NFA::Transition::Invert.new(finish, [*("a".."z"), *("A".."Z"), *("0".."9"), "_"]))
            when %q{\d}
              start.add_transition(NFA::Transition::Range.new(finish, "0", "9"))
            when %q{\D}
              start.add_transition(NFA::Transition::Range.new(finish, "0", "9", invert: true))
            when %q{\h}
              start.add_transition(NFA::Transition::Range.new(finish, "a", "f"))
              start.add_transition(NFA::Transition::Range.new(finish, "A", "F"))
              start.add_transition(NFA::Transition::Range.new(finish, "0", "9"))
            when %q{\H}
              start.add_transition(NFA::Transition::Invert.new(finish, [*("a".."h"), *("A".."H"), *("0".."9")]))
            when %q{\s}
              start.add_transition(NFA::Transition::Value.new(finish, " "))
              start.add_transition(NFA::Transition::Value.new(finish, "\t"))
              start.add_transition(NFA::Transition::Value.new(finish, "\r"))
              start.add_transition(NFA::Transition::Value.new(finish, "\n"))
              start.add_transition(NFA::Transition::Value.new(finish, "\f"))
              start.add_transition(NFA::Transition::Value.new(finish, "\v"))
            when %q{\S}
              start.add_transition(NFA::Transition::Invert.new(finish, [" ", "\t", "\r", "\n", "\f", "\v"]))
            else
              raise
            end
          when CharacterType
            start.add_transition(NFA::Transition::Type.new(finish, node.value))
          when Character
            start.add_transition(NFA::Transition::Value.new(finish, node.value))
          when Period
            transition = NFA::Transition::Any.new(finish)
            start.add_transition(transition)
          when PositiveLookahead
            start.add_transition(NFA::Transition::PositiveLookahead.new(finish, node.value))
          when CharacterRange
            transition = NFA::Transition::Range.new(finish, node.left, node.right)
            start.add_transition(transition)
          when Anchor
            transition =
              case node.value
              when %q{\A}
                NFA::Transition::BeginAnchor.new(finish)
              when %q{\z}, %q{$}
                NFA::Transition::EndAnchor.new(finish)
              end

            start.add_transition(transition)
          when AddEpsilon
            start.add_transition(NFA::Transition::Epsilon.new(finish))
          else
            raise node.inspect
          end
        end

        start_state
      end

      private

      def apply_quantify(quantify)
        work = []

        quantify.transitions.each do |start, finish|
          yield(start, finish, work)
        end

        quantify.after.map { |start, finish| work << [AddEpsilon, start, finish] }

        work.reverse!
      end

      AddEpsilon = Object.new
    end

    class Expression
      attr_reader :items # Group | CaptureGroup | Match | Anchor

      def initialize(items)
        @items = items
      end

      def to_dot(parent)
        node = parent.add_node(object_id, label: "Expression")

        items.each { |item| item.to_dot(node) }
      end

      def to_nfa(start, finish, labels)
        inner = Array.new(items.length - 1) { NFA::State.new(labels.next) }
        states = [start, *inner, finish]

        items.each_with_index do |item, index|
          item.to_nfa(states[index], states[index + 1], labels)
        end
      end
    end

    class Group
      attr_reader :expressions # Array[Expression]
      attr_reader :quantifier # Quantifier

      def initialize(expressions, quantifier: Quantifier::Once.new)
        @expressions = expressions
        @quantifier = quantifier
      end

      def to_dot(parent)
        node = parent.add_node(object_id, label: "Group")

        expressions.each { |expression| expression.to_dot(node) }
        quantifier.to_dot(node)
      end

      def to_nfa(start, finish, labels)
        quantifier.quantify(start, finish, labels) do |qstart, qfinish|
          expressions.each { |expression| expression.to_nfa(qstart, qfinish, labels) }
        end
      end
    end

    class CaptureGroup
      attr_reader :expressions # Array[Expression]
      attr_reader :quantifier # Quantifier
      attr_reader :name # untyped

      def initialize(expressions, quantifier: Quantifier::Once.new, name: nil)
        @expressions = expressions
        @quantifier = quantifier
        @name = name || object_id
      end

      def to_dot(parent)
        node = parent.add_node(object_id, label: "CaptureGroup")

        expressions.each { |expression| expression.to_dot(node) }
        quantifier.to_dot(node)
      end

      def to_nfa(start, finish, labels)
        quantifier.quantify(start, finish, labels) do |quantified_start, quantified_finish|
          capture_start = NFA::State.new
          quantified_start.add_transition(NFA::Transition::StartCapture.new(capture_start, name))

          capture_finish = NFA::State.new
          capture_finish.add_transition(NFA::Transition::EndCapture.new(quantified_finish, name))

          expressions.each { |expression| expression.to_nfa(capture_start, capture_finish, labels) }
        end
      end
    end

    class Match
      attr_reader :item # CharacterGroup | CharacterClass | Character | Period | PositiveLookahead
      attr_reader :quantifier # Quantifier

      def initialize(item, quantifier: Quantifier::Once.new)
        @item = item
        @quantifier = quantifier
      end

      def to_dot(parent)
        node = parent.add_node(object_id, label: "Match")

        item.to_dot(node)
        quantifier.to_dot(node)
      end

      def to_nfa(start, finish, labels)
        quantifier.quantify(start, finish, labels) do |qstart, qfinish|
          item.to_nfa(qstart, qfinish, labels)
        end
      end
    end

    class CharacterGroup
      attr_reader :items # Array[CharacterRange | Character]
      attr_reader :invert # bool

      def initialize(items, invert: false)
        @items = items
        @invert = invert
      end

      def to_dot(parent)
        label = "CharacterGroup"
        label = "#{label} (invert)" if invert

        node = parent.add_node(object_id, label: label)
        items.each { |item| item.to_dot(node) }
      end

      def to_nfa(start, finish, labels)
        if invert
          transition = NFA::Transition::Invert.new(finish, items.flat_map(&:to_nfa_values).sort)
          start.add_transition(transition)
        else
          items.each do |item|
            item.to_nfa(start, finish, labels)
          end
        end
      end
    end

    class CharacterClass
      attr_reader :value # "\w" | "\W" | "\d" | "\D" | "\h" | "\H" | "\s" | "\S"

      def initialize(value)
        @value = value
      end

      def to_dot(parent)
        parent.add_node(object_id, label: value, shape: "box")
      end

      def to_nfa(start, finish, _labels)
        case value
        when %q{\w}
          start.add_transition(NFA::Transition::Range.new(finish, "a", "z"))
          start.add_transition(NFA::Transition::Range.new(finish, "A", "Z"))
          start.add_transition(NFA::Transition::Range.new(finish, "0", "9"))
          start.add_transition(NFA::Transition::Value.new(finish, "_"))
        when %q{\W}
          start.add_transition(NFA::Transition::Invert.new(finish, [*("a".."z"), *("A".."Z"), *("0".."9"), "_"]))
        when %q{\d}
          start.add_transition(NFA::Transition::Range.new(finish, "0", "9"))
        when %q{\D}
          start.add_transition(NFA::Transition::Range.new(finish, "0", "9", invert: true))
        when %q{\h}
          start.add_transition(NFA::Transition::Range.new(finish, "a", "f"))
          start.add_transition(NFA::Transition::Range.new(finish, "A", "F"))
          start.add_transition(NFA::Transition::Range.new(finish, "0", "9"))
        when %q{\H}
          start.add_transition(NFA::Transition::Invert.new(finish, [*("a".."h"), *("A".."H"), *("0".."9")]))
        when %q{\s}
          start.add_transition(NFA::Transition::Value.new(finish, " "))
          start.add_transition(NFA::Transition::Value.new(finish, "\t"))
          start.add_transition(NFA::Transition::Value.new(finish, "\r"))
          start.add_transition(NFA::Transition::Value.new(finish, "\n"))
          start.add_transition(NFA::Transition::Value.new(finish, "\f"))
          start.add_transition(NFA::Transition::Value.new(finish, "\v"))
        when %q{\S}
          start.add_transition(NFA::Transition::Invert.new(finish, [" ", "\t", "\r", "\n", "\f", "\v"]))
        else
          raise
        end
      end
    end

    class CharacterType
      attr_reader :value # "alnum" | "alpha" | "lower" | "upper"

      def initialize(value)
        @value = value
      end

      def to_dot(parent)
        parent.add_node(object_id, label: "[[:#{value}:]]", shape: "box")
      end

      def to_nfa(start, finish, _labels)
        start.add_transition(NFA::Transition::Type.new(finish, value))
      end
    end

    class Character
      attr_reader :value # String

      def initialize(value)
        @value = value
      end

      def to_dot(parent)
        parent.add_node(object_id, label: value, shape: "box")
      end

      def to_nfa_values
        [value]
      end

      def to_nfa(start, finish, _labels)
        start.add_transition(NFA::Transition::Value.new(finish, value))
      end
    end

    class Period
      def to_dot(parent)
        parent.add_node(object_id, label: ".", shape: "box")
      end

      def to_nfa(start, finish, _labels)
        transition = NFA::Transition::Any.new(finish)
        start.add_transition(transition)
      end
    end

    class PositiveLookahead
      attr_reader :values # Array[Character]

      def initialize(values)
        @values = values
      end

      def value
        values.map(&:value).join
      end

      def to_dot(parent)
        parent.add_node(object_id, label: "(?=#{value})", shape: "box")
      end

      def to_nfa(start, finish, _labels)
        start.add_transition(NFA::Transition::PositiveLookahead.new(finish, value))
      end
    end

    class CharacterRange
      attr_reader :left, :right # String

      def initialize(left, right)
        @left = left
        @right = right
      end

      def to_dot(parent)
        parent.add_node(object_id, label: "#{left}-#{right}", shape: "box")
      end

      def to_nfa_values
        (left..right).to_a
      end

      def to_nfa(start, finish, _labels)
        transition = NFA::Transition::Range.new(finish, left, right)
        start.add_transition(transition)
      end
    end

    class Anchor
      attr_reader :value # "\A" | "\z" | "$"

      def initialize(value)
        @value = value
      end

      def to_dot(parent)
        parent.add_node(object_id, label: value, shape: "box")
      end

      def to_nfa(start, finish, _labels)
        transition =
          case value
          when %q{\A}
            NFA::Transition::BeginAnchor.new(finish)
          when %q{\z}, %q{$}
            NFA::Transition::EndAnchor.new(finish)
          end

        start.add_transition(transition)
      end
    end

    module Quantifier
      class Once
        def to_dot(parent); end

        def quantify(start, finish, _labels)
          QuantifyResult.new([[start, finish]])
        end
      end

      class ZeroOrMore
        def to_dot(parent)
          parent.add_node(object_id, label: "*", shape: "box")
        end

        def quantify(start, finish, _labels)
          QuantifyResult.new([[start, start]], after: [[start, finish]])
        end
      end

      class OneOrMore
        def to_dot(parent)
          parent.add_node(object_id, label: "+", shape: "box")
        end

        def quantify(start, finish, _labels)
          QuantifyResult.new([[start, finish]], after: [[finish, start]])
        end
      end

      class Optional
        def to_dot(parent)
          parent.add_node(object_id, label: "?", shape: "box")
        end

        def quantify(start, finish, _labels)
          QuantifyResult.new([[start, finish]], after: [[start, finish]])
        end
      end

      class Exact
        attr_reader :value # Integer

        def initialize(value)
          @value = value
        end

        def to_dot(parent)
          parent.add_node(object_id, label: "{#{value}}", shape: "box")
        end

        def quantify(start, finish, labels)
          states = [start, *(value - 1).times.map { NFA::State.new(labels.next) }, finish]

          transitions = value.times.map do |index|
            [states[index], states[index + 1]]
          end

          QuantifyResult.new(transitions)
        end
      end

      class AtLeast
        attr_reader :value # Integer

        def initialize(value)
          @value = value
        end

        def to_dot(parent)
          parent.add_node(object_id, label: "{#{value},}", shape: "box")
        end

        def quantify(start, finish, labels)
          states = [start, *(value - 1).times.map { NFA::State.new(labels.next) }, finish]

          transitions = value.times.map do |index|
            [states[index], states[index + 1]]
          end

          after = [[states[-1], states[-2]]]
          QuantifyResult.new(transitions, after: after)
        end
      end

      class Range
        attr_reader :lower, :upper # Integer

        def initialize(lower, upper)
          @lower = lower
          @upper = upper
        end

        def to_dot(parent)
          parent.add_node(object_id, label: "{#{lower},#{upper}}", shape: "box")
        end

        def quantify(start, finish, labels)
          states = [start, *(upper - 1).times.map { NFA::State.new(labels.next) }, finish]

          transitions = upper.times.map do |index|
            [states[index], states[index + 1]]
          end

          after = (upper - lower).times.map do |index|
            [states[lower + index], states[-1]]
          end

          QuantifyResult.new(transitions, after: after)
        end
      end

      class QuantifyResult
        attr_reader :transitions, :after # [(state, state)]

        def initialize(transitions, after: [])
          @transitions = transitions
          @after = after
        end
      end
      private_constant(:QuantifyResult)
    end
  end
end
