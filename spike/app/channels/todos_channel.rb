# frozen_string_literal: true

# Stage-2 spike channel: same cable architecture as CounterChannel, but the
# render target is a Phlex component re-rendered ON THE SAME INSTANCE
# (signal identity lives in the instance, so re-instantiating would reset
# state). One render effect per component — this is the hibiki_phlex
# `render_effect` prototype.
class TodosChannel < ApplicationCable::Channel
  def subscribed
    @cid = params[:cid]
    return reject if @cid.blank?

    @actor = GraphActor.new
    @actor.post { build_graph }
  end

  def unsubscribed
    return unless @actor

    @actor.post { @root.dispose }
    @actor.stop
  end

  def add(data)
    title = data["title"].to_s.strip
    act { @list.add(title) } unless title.empty?
  end

  def toggle(data)
    index = data["index"].to_i
    act { @list.toggle(index) }
  end

  private

  def act(&mutation)
    @actor.post { Hibiki.batch(&mutation) }
  end

  def build_graph
    @root = Hibiki.root do
      @list = TodoList.new

      # The render effect: its first run performs the dep-collecting initial
      # render (signals read inside view_template subscribe it, through
      # plain method calls); each rerun re-renders the same instance.
      Hibiki::Effect.new do
        html = @list.rerender
        Rails.logger.info("[hibiki-spike] render_effect TodoList (#{html.bytesize} bytes)")
        Turbo::StreamsChannel.broadcast_replace_to("todos", @cid, target: "todos", html:)
      end
    end
  end
end
