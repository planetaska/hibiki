# frozen_string_literal: true

# Stage-2 spike channel, now the live proof of hibiki_phlex composing with
# hibiki_rails: one render effect per component, re-rendered ON THE SAME
# INSTANCE (signal identity lives in the instance, so re-instantiating
# would reset state), HTML transmitted over the channel's own subscription
# — the packaged client swaps it in by the fragment's DOM id ("todos").
class TodosChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  def build_graph
    @list = TodoList.new

    # First run = the dep-collecting initial render (signals read inside
    # view_template subscribe it, through plain method calls).
    Hibiki::Phlex.render_effect(@list) do |html|
      Rails.logger.info("[hibiki-spike] render_effect TodoList (#{html.bytesize} bytes)")
      transmit({ html: })
    end
  end

  def add(data)
    title = data["title"].to_s.strip
    @list.add(title) unless title.empty?
  end

  def toggle(data) = @list.toggle(data["index"].to_i)
end
