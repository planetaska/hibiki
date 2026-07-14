# frozen_string_literal: true

# A rendered fragment: takes the graph's signals and reads .value inside
# view_template, so a render_effect wrapping #rerender tracks them. The
# root element's DOM id is the replacement key the client driver uses.
class Counter::CountDisplay < Phlex::HTML
  include Hibiki::Phlex::Rerenderable

  def initialize(count:, doubled:)
    @count = count
    @doubled = doubled
  end

  def view_template
    p(id: "count") do
      plain "count: "
      strong { @count.value.to_s }
      plain " · doubled: "
      strong { @doubled.value.to_s }
    end
  end
end
