# frozen_string_literal: true

# Hibiki — a minimal Svelte-5-style signal system in Ruby.
#
# Three primitives, same as Solid/Svelte 5 internals:
#   state(v)      -> writable signal
#   derived { }   -> lazy computed signal with runtime dependency tracking
#   effect { }    -> side effect that re-runs when its dependencies change
#
# Dependency tracking works exactly like the JS frameworks: while a derived
# or effect is (re)computing, it is pushed onto an "observer stack". Any
# signal whose value is READ during that window registers the observer as a
# subscriber. Writes then invalidate subscribers transitively.

require "set" # core class on Ruby >= 4.0; kept for the 3.4 floor

require_relative "hibiki/version"
require_relative "hibiki/tracking"
require_relative "hibiki/state"
require_relative "hibiki/derived"
require_relative "hibiki/effect"
require_relative "hibiki/dsl"
