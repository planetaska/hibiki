# frozen_string_literal: true

module Hibiki
  # ---- top-level DSL ----------------------------------------------------------
  # Opt-in: `include Hibiki::DSL` where you want the bare helpers.
  # The gem never includes it for you (no polluting Object/main).
  module DSL
    def state(value, equals: nil) = State.new(value, equals:)
    def derived(equals: nil, &) = Derived.new(equals:, &)
    def effect(scheduler: nil, &) = Effect.new(scheduler:, &)
    def batch(&)   = Hibiki.batch(&)
    def root(&)    = Hibiki.root(&)
    def on_cleanup(&) = Hibiki.on_cleanup(&)
  end
end
