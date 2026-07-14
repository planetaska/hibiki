# frozen_string_literal: true

require "spec_helper"

# The guard spec: pins the upstream Phlex internals Rerenderable leans on,
# so bumping the gemspec's Phlex bound fails HERE, loudly, instead of
# silently double-render-raising (or worse) in apps. If one of these breaks
# on a new Phlex, re-derive the shim before widening the pin.
RSpec.describe "Phlex rendering contract" do
  let(:component_class) do
    Class.new(Phlex::HTML) do
      def view_template = p { "hi" }
    end
  end

  it "spends an instance through @_state alone: set after a render" do
    component = component_class.new
    component.call
    expect(component.instance_variable_get(:@_state)).to be_truthy
  end

  it "raises DoubleRenderError on a second render while @_state is set" do
    component = component_class.new
    component.call
    expect { component.call }.to raise_error(Phlex::DoubleRenderError)
  end

  it "un-spends the instance when @_state is cleared — the whole shim" do
    component = component_class.new
    first = component.call
    component.instance_variable_set(:@_state, nil)
    expect(component.call).to eq(first)
  end

  it "reports rendering? straight off @_state" do
    component = component_class.new
    expect(component.rendering?).to be(false)
    component.call
    expect(component.rendering?).to be(true)
  end
end
