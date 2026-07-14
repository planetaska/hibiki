# frozen_string_literal: true

require "spec_helper"

RSpec.describe Hibiki::Phlex::Rerenderable do
  let(:component_class) do
    Class.new(Phlex::HTML) do
      include Hibiki::Phlex::Rerenderable

      def initialize(label = "one") # rubocop:disable Lint/MissingSuper -- Phlex::HTML has no initialize
        @label = label
      end

      attr_accessor :label

      def view_template = span { @label }
    end
  end

  it "renders the same instance repeatedly where bare #call raises" do
    component = component_class.new
    expect(component.rerender).to eq("<span>one</span>")
    expect(component.rerender).to eq("<span>one</span>")
  end

  it "reflects current instance state on each rerender" do
    component = component_class.new
    component.rerender
    component.label = "two"
    expect(component.rerender).to eq("<span>two</span>")
  end

  it "forwards call arguments (an existing buffer)" do
    component = component_class.new
    buffer = +"<!-- prefix -->"
    expect(component.rerender(buffer)).to eq("<!-- prefix --><span>one</span>")
  end
end
