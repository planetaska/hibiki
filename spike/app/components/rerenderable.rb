# frozen_string_literal: true

# The Phase-2 answer to "can Phlex re-render the same instance?": yes.
# Phlex 2 marks an instance as spent purely through @_state —
# SGML#internal_call raises DoubleRenderError when it is set, and it is
# deliberately never cleared after a render (see `rendering?`). Everything
# else (output buffer, capture state, the thread-local current component)
# is per-call, so clearing @_state before calling again is the ENTIRE
# adapter. hibiki_phlex would own this shim and pin it to Phlex versions,
# since it leans on a private ivar.
module Rerenderable
  def rerender(...)
    @_state = nil
    call(...)
  end
end
