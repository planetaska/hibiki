# frozen_string_literal: true

# The second, independent fragment: writing `step` re-renders only this
# component (fine-grained re-render, same proof as the spike's #step
# partial). Kept separate from the step INPUT, which lives un-replaced in
# Counter::Show so re-renders never clobber what the user is typing.
class Counter::StepDisplay < Phlex::HTML
  include Hibiki::Phlex::Rerenderable

  def initialize(step:)
    @step = step
  end

  def view_template
    p(id: "step") do
      plain "step: "
      strong { @step.value.to_s }
    end
  end
end
