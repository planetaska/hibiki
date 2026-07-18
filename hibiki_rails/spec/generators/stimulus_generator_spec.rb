# frozen_string_literal: true

require "rails_helper"
require "support/generator_harness"

RSpec.describe Hibiki::Rails::Generators::StimulusGenerator do
  include GeneratorHarness

  around do |example|
    Dir.mktmpdir do |dir|
      @destination = dir
      example.run
    end
  end

  def generated(path) = File.read(File.join(@destination, path))

  it "generates channel, controller, and views under the default view dir" do
    run_generator(described_class, ["counter"], destination: @destination)

    channel = generated("app/channels/counter_channel.rb")
    expect(channel).to include("class CounterChannel < ApplicationCable::Channel")
      .and include("include Hibiki::Rails::Channel")
      .and include('target: "counter_display"')
      .and include('partial: "counter/counter_display"')

    controller = generated("app/javascript/controllers/counter_controller.js")
    expect(controller).to include("extends ChannelController")
    expect(controller).not_to include("static channel")

    island = generated("app/views/counter/_counter.html.erb")
    expect(island).to include('data-controller="counter"')
      .and include('data-counter-cid-value="<%= cid %>"')
      .and include('turbo_stream_from "counter", cid')
      .and include('data-action="counter#increment"')

    # The broadcast replacement key: display root id == channel target.
    expect(generated("app/views/counter/_counter_display.html.erb"))
      .to include('id="counter_display"')
  end

  it "puts views under an explicit view_path" do
    run_generator(described_class, %w[counter widgets], destination: @destination)

    expect(generated("app/views/widgets/_counter.html.erb"))
      .to include('render "widgets/counter_display"')
    expect(generated("app/channels/counter_channel.rb"))
      .to include('partial: "widgets/counter_display"')
  end

  it "pins the channel name for namespaced components" do
    run_generator(described_class, ["admin/counter"], destination: @destination)

    expect(generated("app/javascript/controllers/admin/counter_controller.js"))
      .to include('static channel = "Admin::CounterChannel"')
    expect(generated("app/channels/admin/counter_channel.rb"))
      .to include("class Admin::CounterChannel < ApplicationCable::Channel")

    island = generated("app/views/admin/counter/_counter.html.erb")
    expect(island).to include('data-controller="admin--counter"')
      .and include('turbo_stream_from "admin:counter", cid')
  end

  it "emits syntactically valid Ruby and ERB" do
    run_generator(described_class, ["admin/counter"], destination: @destination)

    expect_valid_generated_sources(@destination)
  end
end
