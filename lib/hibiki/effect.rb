# frozen_string_literal: true

module Hibiki
  # ---- effect -----------------------------------------------------------------
  class Effect
    def initialize(&block)
      @block = block
      run
    end

    def invalidate = run

    private

    def run
      Hibiki.track(self) { @block.call }
    end
  end
end
