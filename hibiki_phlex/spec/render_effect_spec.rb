# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Hibiki::Phlex.render_effect" do
  let(:counter_class) do
    Class.new(Phlex::HTML) do
      include Hibiki::Reactive
      include Hibiki::Phlex::Rerenderable

      state(:count) { 0 }
      derived(:double) { count * 2 }

      def view_template = p { "count=#{count} double=#{double}" }
    end
  end

  def collect_renders(component, **)
    renders = []
    effect = Hibiki::Phlex.render_effect(component, **) { |html| renders << html }
    [renders, effect]
  end

  it "yields the dependency-collecting initial render once, immediately" do
    renders, = collect_renders(counter_class.new)
    expect(renders).to eq(["<p>count=0 double=0</p>"])
  end

  it "re-renders the same instance and yields fresh HTML on a write" do
    component = counter_class.new
    renders, = collect_renders(component)
    component.count = 3
    expect(renders.last).to eq("<p>count=3 double=6</p>")
    expect(renders.size).to eq(2)
  end

  it "does not re-render on an equal (==) write" do
    component = counter_class.new
    renders, = collect_renders(component)
    component.count = 0
    expect(renders.size).to eq(1)
  end

  it "coalesces a batch of writes into one re-render" do
    component = counter_class.new
    renders, = collect_renders(component)
    Hibiki.batch do
      component.count = 1
      component.count = 2
      component.count = 3
    end
    expect(renders.size).to eq(2)
    expect(renders.last).to eq("<p>count=3 double=6</p>")
  end

  it "re-collects dependencies each rerun (flag ? a : b through the template)" do
    switch_class = Class.new(Phlex::HTML) do
      include Hibiki::Reactive
      include Hibiki::Phlex::Rerenderable

      state(:flag) { true }
      state(:a) { "A" }
      state(:b) { "B" }

      def view_template = p { flag ? a : b }
    end

    component = switch_class.new
    renders, = collect_renders(component)

    component.b = "B2" # untracked branch — no rerun
    expect(renders.size).to eq(1)

    component.flag = false
    expect(renders.last).to eq("<p>B2</p>")

    component.a = "A2" # now a is the untracked one
    expect(renders.size).to eq(2)
    component.b = "B3"
    expect(renders.last).to eq("<p>B3</p>")
  end

  it "stops re-rendering once the effect is disposed" do
    component = counter_class.new
    renders, effect = collect_renders(component)
    effect.dispose
    component.count = 9
    expect(renders.size).to eq(1)
  end

  it "is torn down by the root that owns it" do
    component = counter_class.new
    renders = []
    root = Hibiki.root do
      Hibiki::Phlex.render_effect(component) { |html| renders << html }
    end
    root.dispose
    component.count = 9
    expect(renders).to eq(["<p>count=0 double=0</p>"])
  end

  it "hands reruns to scheduler: instead of rendering, until #run" do
    component = counter_class.new
    scheduled = []
    renders, = collect_renders(component, scheduler: ->(effect) { scheduled << effect })

    component.count = 5
    expect(renders.size).to eq(1) # deferred, not rendered
    expect(scheduled.size).to eq(1)

    scheduled.first.run
    expect(renders.last).to eq("<p>count=5 double=10</p>")
  end

  it "rejects a component without #rerender at creation time" do
    plain = Class.new(Phlex::HTML) do
      def view_template = p { "static" }
    end

    expect do
      Hibiki::Phlex.render_effect(plain.new) { |html| html }
    end.to raise_error(ArgumentError, /Rerenderable/)
  end
end
