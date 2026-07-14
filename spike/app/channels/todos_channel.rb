# frozen_string_literal: true

# Stage-2 spike channel on hibiki_rails: the render target is a Phlex
# component re-rendered ON THE SAME INSTANCE (signal identity lives in the
# instance, so re-instantiating would reset state). One render effect per
# component — this is the hibiki_phlex `render_effect` prototype, kept
# spike-local until Phase 4.
class TodosChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  def build_graph
    @list = TodoList.new

    # The render effect: its first run performs the dep-collecting initial
    # render (signals read inside view_template subscribe it, through
    # plain method calls); each rerun re-renders the same instance.
    Hibiki::Effect.new do
      html = @list.rerender
      Rails.logger.info("[hibiki-spike] render_effect TodoList (#{html.bytesize} bytes)")
      broadcast_replace target: "todos", html:
    end
  end

  def add(data)
    title = data["title"].to_s.strip
    @list.add(title) unless title.empty?
  end

  def toggle(data) = @list.toggle(data["index"].to_i)
end
