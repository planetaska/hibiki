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

  describe "index.js registration (jsbundling apps have no eager loader)" do
    let(:index_js) { "app/javascript/controllers/index.js" }

    def write(path, content)
      full = File.join(@destination, path)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
    end

    it "appends the import/register pair when there is no importmap" do
      write(index_js, %(import { application } from "./application"\n))

      run_generator(described_class, ["admin/counter"], destination: @destination)

      expect(generated(index_js))
        .to include('import Admin__CounterController from "./admin/counter_controller"')
        .and include('application.register("admin--counter", Admin__CounterController)')
    end

    it "registers once no matter how often it reruns" do
      write(index_js, %(import { application } from "./application"\n))

      run_generator(described_class, ["counter"], destination: @destination)
      output = run_generator(described_class, ["counter"], destination: @destination)

      expect(output).to include("identical")
      expect(generated(index_js).scan('application.register("counter"').size).to eq(1)
    end

    it "leaves index.js alone in importmap apps" do
      write("config/importmap.rb", "")
      write(index_js, %(import { application } from "./application"\n))

      run_generator(described_class, ["counter"], destination: @destination)

      expect(generated(index_js)).not_to include("application.register")
    end

    it "prints the registration for hand-wiring when index.js is missing" do
      output = run_generator(described_class, ["counter"], destination: @destination)

      expect(output).to include("add this yourself")
        .and include('application.register("counter", CounterController)')
    end
  end
end
