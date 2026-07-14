# frozen_string_literal: true

# NOTE: for everything under lib/hibiki/phlex/ — inside this namespace a bare
# `Phlex` constant resolves to Hibiki::Phlex, not the framework. Always
# write `::Phlex.` when you mean the framework.
module Hibiki
  # Phlex glue for hibiki: a component is a plain Ruby object, so
  # Hibiki::Reactive gives it signals read as ordinary method calls, and a
  # render effect re-renders the same instance (signal identity lives in
  # the instance) whenever one of them changes.
  module Phlex
    # Wrap a component's render in an effect. The effect's first run is the
    # dependency-collecting initial render — signals read inside
    # view_template subscribe it through plain method calls — and its HTML
    # is yielded like every rerun's. On each signal change the component
    # re-renders ON THE SAME INSTANCE and the fresh HTML goes to the block;
    # the block owns the transport (broadcast it, print it, diff it).
    #
    #   Hibiki::Phlex.render_effect(@list) do |html|
    #     broadcast_replace target: "todos", html:
    #   end
    #
    # Component-grained by design: one effect per component (the ERB style
    # in hibiki_rails is one effect per partial — both are correct).
    # `scheduler:` passes through to Hibiki::Effect, so reruns can be
    # deferred/debounced (e.g. Hibiki::Rails::Debounce). Returns the Effect;
    # inside a Hibiki.root or another effect the owner tree adopts it, a
    # bare caller disposes it by hand.
    def self.render_effect(component, scheduler: nil, &sink)
      unless component.respond_to?(:rerender)
        raise ArgumentError,
              "#{component.class} has no #rerender — include Hibiki::Phlex::Rerenderable"
      end

      Effect.new(scheduler:) { sink.call(component.rerender) }
    end
  end
end

require_relative "phlex/version"
require_relative "phlex/rerenderable"
