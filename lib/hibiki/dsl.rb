# frozen_string_literal: true

module Hibiki
  # ---- top-level DSL ----------------------------------------------------------
  # Opt-in: `include Hibiki::DSL` where you want the bare helpers.
  # The gem never includes it for you (no polluting Object/main).
  module DSL
    def state(value) = State.new(value)
    def derived(&) = Derived.new(&)
    def effect(&)  = Effect.new(&)
    def batch(&)   = Hibiki.batch(&)
    def root(&)    = Hibiki.root(&)
    def on_cleanup(&) = Hibiki.on_cleanup(&)
  end
end
