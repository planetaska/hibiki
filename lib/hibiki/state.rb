# frozen_string_literal: true

module Hibiki
  # ---- writable signal --------------------------------------------------------
  class State
    include Trackable

    def initialize(value)
      @value = value
    end

    def value
      register_dependency
      @value
    end

    def value=(new_value)
      return if new_value == @value

      @value = new_value
      notify
    end

    # sugar for in-place updates: counter.update { it + 1 }
    def update = self.value = yield(@value)

    def to_s = value.to_s
    def inspect = "#<Hibiki::State #{@value.inspect}>"
  end
end
