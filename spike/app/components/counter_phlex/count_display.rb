# frozen_string_literal: true

# A rendered fragment in the signal-passing style (contrast TodoList's
# Hibiki::Reactive style): the graph's signals come in as constructor args
# and are read with `.value` inside view_template, so a render_effect
# wrapping #rerender tracks them. The root element's DOM id is the
# replacement key the packaged client swaps on.
class CounterPhlex::CountDisplay < Phlex::HTML
  include Hibiki::Phlex::Rerenderable

  def initialize(count:, doubled:)
    @count = count
    @doubled = doubled
  end

  def view_template
    p(id: "phlex-count") do
      plain "count: "
      strong { @count.value.to_s }
      plain " · doubled: "
      strong { @doubled.value.to_s }
    end
  end
end
