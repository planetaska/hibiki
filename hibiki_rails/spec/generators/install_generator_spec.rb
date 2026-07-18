# frozen_string_literal: true

require "rails_helper"
require "support/generator_harness"

RSpec.describe Hibiki::Rails::Generators::InstallGenerator do
  include GeneratorHarness

  around do |example|
    Dir.mktmpdir do |dir|
      @destination = dir
      example.run
    end
  end

  let(:index_js) { File.join(@destination, "app/javascript/controllers/index.js") }
  let(:application_helper) { File.join(@destination, "app/helpers/application_helper.rb") }
  let(:importmap) { File.join(@destination, "config/importmap.rb") }
  let(:cable_channel) { File.join(@destination, "app/channels/application_cable/channel.rb") }
  let(:cable_connection) { File.join(@destination, "app/channels/application_cable/connection.rb") }

  # The stock Rails 8 importmap app shapes the wiring targets start in
  # (no app/channels, no @rails/actioncable pin — both appear only after
  # a first `rails g channel`, which most apps never run).
  def seed_stock_app
    FileUtils.mkdir_p(File.dirname(index_js))
    File.write(index_js, <<~JS)
      import { application } from "controllers/application"
      import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
      eagerLoadControllersFrom("controllers", application)
    JS
    FileUtils.mkdir_p(File.dirname(application_helper))
    File.write(application_helper, "module ApplicationHelper\nend\n")
    FileUtils.mkdir_p(File.dirname(importmap))
    File.write(importmap, <<~RUBY)
      pin "application"
      pin "@hotwired/turbo-rails", to: "turbo.min.js"
    RUBY
  end

  it "registers the packaged controller and includes the helpers" do
    seed_stock_app
    run_generator(described_class, destination: @destination)

    expect(File.read(index_js)).to include('import HibikiController from "hibiki"')
      .and include('application.register("hibiki", HibikiController)')
    expect(File.read(application_helper))
      .to include("module ApplicationHelper\n  include Hibiki::Rails::Helpers\nend")
  end

  it "creates the ApplicationCable boilerplate and pins @rails/actioncable" do
    seed_stock_app
    run_generator(described_class, destination: @destination)

    expect(File.read(cable_channel)).to include("class Channel < ActionCable::Channel::Base")
    expect(File.read(cable_connection)).to include("class Connection < ActionCable::Connection::Base")
    expect(File.read(importmap)).to include('pin "@rails/actioncable", to: "actioncable.esm.js"')
    expect_valid_generated_sources(@destination)
  end

  it "is idempotent: a second run changes nothing" do
    seed_stock_app
    run_generator(described_class, destination: @destination)
    output = run_generator(described_class, destination: @destination)

    expect(output).to include("identical")
    expect(File.read(index_js).scan('application.register("hibiki"').count).to eq(1)
    expect(File.read(application_helper).scan("Hibiki::Rails::Helpers").count).to eq(1)
    expect(File.read(importmap).scan("@rails/actioncable").count).to eq(1)
  end

  it "never touches an existing ApplicationCable" do
    seed_stock_app
    FileUtils.mkdir_p(File.dirname(cable_channel))
    custom = <<~RUBY
      module ApplicationCable
        class Channel < ActionCable::Channel::Base
          periodically :beat, every: 2
        end
      end
    RUBY
    File.write(cable_channel, custom)
    run_generator(described_class, destination: @destination)

    expect(File.read(cable_channel)).to eq(custom)
    expect(File.exist?(cable_connection)).to be(true)
  end

  it "prints manual instructions when the wiring targets are missing" do
    output = run_generator(described_class, destination: @destination)

    expect(output).to include("add this yourself")
    expect(output).to include('application.register("hibiki", HibikiController)')
    expect(output).to include("include Hibiki::Rails::Helpers")
    expect(File.exist?(index_js)).to be(false)
  end

  it "points bundler apps at the npm package instead of pinning" do
    output = run_generator(described_class, destination: @destination)

    expect(output).to include("npm/yarn add @rails/actioncable")
    expect(File.exist?(importmap)).to be(false)
    expect(File.exist?(cable_channel)).to be(true)
  end
end
