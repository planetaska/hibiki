# frozen_string_literal: true

module Hibiki
  module Phlex
    # Lets the same component instance render more than once — required for
    # render_effect, where signal identity lives in the instance (a fresh
    # instance per render would reset every signal).
    #
    # Phlex 2 marks an instance as spent purely through @_state —
    # SGML#internal_call raises DoubleRenderError when it is set, and it is
    # deliberately never cleared after a render (see `rendering?`).
    # Everything else (output buffer, capture state, the thread-local
    # current component) is per-call, so clearing @_state before calling
    # again is the ENTIRE adapter. It leans on a private ivar, which is why
    # this gem pins Phlex minors and spec/phlex_contract_spec.rb pins the
    # contract itself.
    module Rerenderable
      def rerender(...)
        @_state = nil
        call(...)
      end
    end
  end
end
