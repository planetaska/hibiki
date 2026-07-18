# frozen_string_literal: true

require "rails_helper"
require "support/generator_harness"

RSpec.describe Hibiki::Rails::Generators::IslandGenerator do
  include GeneratorHarness

  around do |example|
    Dir.mktmpdir do |dir|
      @destination = dir
      example.run
    end
  end

  def generated(path) = File.read(File.join(@destination, path))

  it "generates a channel and a helpers-stamped island, no JS" do
    run_generator(described_class, ["widget"], destination: @destination)

    expect(generated("app/channels/widget_channel.rb"))
      .to include("class WidgetChannel < ApplicationCable::Channel")
      .and include('target: "widget_display"')

    island = generated("app/views/widget/_widget.html.erb")
    expect(island).to include("hibiki_island(WidgetChannel, cid:)")
      .and include('turbo_stream_from "widget", cid')
      .and include("on(:increment)")
    expect(generated("app/views/widget/_widget_display.html.erb"))
      .to include('id="widget_display"')

    expect(Dir[File.join(@destination, "app/javascript/**/*.js")]).to be_empty
  end

  # Regression guard on the Phase 4.5 private-contract rule: generated
  # views go through the Helpers, never the raw attribute names.
  it "never emits literal data-hibiki attributes" do
    run_generator(described_class, ["widget"], destination: @destination)

    Dir[File.join(@destination, "app/views/**/*.erb")].each do |view|
      expect(File.read(view)).not_to include("data-hibiki")
    end
  end

  it "hints at hibiki:rails:install when the wiring is missing" do
    output = run_generator(described_class, ["widget"], destination: @destination)

    expect(output).to include("bin/rails g hibiki:rails:install")
  end

  it "stays quiet when the app is already wired" do
    FileUtils.mkdir_p(File.join(@destination, "app/javascript/controllers"))
    File.write(File.join(@destination, "app/javascript/controllers/index.js"),
               "application.register(\"hibiki\", HibikiController)\n")
    FileUtils.mkdir_p(File.join(@destination, "app/helpers"))
    File.write(File.join(@destination, "app/helpers/application_helper.rb"),
               "module ApplicationHelper\n  include Hibiki::Rails::Helpers\nend\n")

    output = run_generator(described_class, ["widget"], destination: @destination)

    expect(output).not_to include("hibiki:rails:install")
  end

  it "emits syntactically valid Ruby and ERB" do
    run_generator(described_class, ["admin/widget"], destination: @destination)

    expect_valid_generated_sources(@destination)
  end
end
