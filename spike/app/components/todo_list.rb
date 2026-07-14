# frozen_string_literal: true

# The Phlex payoff this stage exists to demonstrate: the component is a
# plain Ruby object, so `include Hibiki::Reactive` gives it per-instance
# signals read as ordinary method calls — no `.value` anywhere in
# view_template, yet a render effect wrapping `rerender` tracks them.
#
# Items are immutable rows in a value-replaced array: signals compare with
# `==` and never see in-place mutation, so add/toggle build a new array.
class TodoList < Phlex::HTML
  include Hibiki::Reactive
  include Hibiki::Phlex::Rerenderable

  state(:items) { [] } # array of { title:, done: }
  derived(:remaining) { items.count { |item| !item[:done] } }

  def view_template
    div(id: "todos") do
      h2 { "Todos — #{remaining} remaining" }
      ul do
        items.each_with_index do |item, index|
          li do
            button(data: { action: "todos#toggle", todos_index_param: index }) do
              item[:done] ? "☑" : "☐"
            end
            span { " #{item[:title]}" }
          end
        end
      end
    end
  end

  def add(title)
    self.items = items + [{ title:, done: false }]
  end

  def toggle(index)
    self.items = items.each_with_index.map do |item, i|
      i == index ? item.merge(done: !item[:done]) : item
    end
  end
end
