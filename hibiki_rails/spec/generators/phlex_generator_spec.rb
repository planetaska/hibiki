# frozen_string_literal: true

require "rails_helper"
require "support/generator_harness"

RSpec.describe Hibiki::Rails::Generators::PhlexGenerator do
  include GeneratorHarness

  around do |example|
    Dir.mktmpdir do |dir|
      @destination = dir
      example.run
    end
  end

  def generated(path) = File.read(File.join(@destination, path))

  it "generates channel, component, and island wrapper" do
    run_generator(described_class, ["gadget"], destination: @destination)

    expect(generated("app/channels/gadget_channel.rb"))
      .to include("class GadgetChannel < ApplicationCable::Channel")
      .and include("Hibiki::Phlex.render_effect(@component) { |html| transmit({ html: }) }")

    component = generated("app/components/gadget.rb")
    expect(component).to include("class Gadget < Phlex::HTML")
      .and include("include Hibiki::Reactive")
      .and include("include Hibiki::Phlex::Rerenderable")
      .and include("include Hibiki::Rails::Helpers")
      .and include('div(id: "gadget")')
      .and include("on(:increment)")

    expect(generated("app/components/gadget_island.rb"))
      .to include("class GadgetIsland < Phlex::HTML")
      .and include("hibiki_island(GadgetChannel, cid: SecureRandom.uuid)")
  end

  # hibiki_phlex is deliberately not in this gem's bundle (the phlex glue
  # stays a separate gem), so CI exercises the LoadError branch; in an app
  # that bundles hibiki_phlex the warning stays silent.
  it "warns that hibiki_phlex is missing from this bundle" do
    output = run_generator(described_class, ["gadget"], destination: @destination)

    expect(output).to include("hibiki_phlex is not in this bundle")
  end

  it "hints at hibiki:rails:install when the register line is missing" do
    output = run_generator(described_class, ["gadget"], destination: @destination)

    expect(output).to include("bin/rails g hibiki:rails:install")
  end

  it "stays quiet about wiring when the register line exists" do
    FileUtils.mkdir_p(File.join(@destination, "app/javascript/controllers"))
    File.write(File.join(@destination, "app/javascript/controllers/index.js"),
               "application.register(\"hibiki\", HibikiController)\n")

    output = run_generator(described_class, ["gadget"], destination: @destination)

    expect(output).not_to include("bin/rails g hibiki:rails:install")
  end

  it "emits syntactically valid Ruby, namespaced included" do
    run_generator(described_class, ["admin/gadget"], destination: @destination)

    expect(generated("app/components/admin/gadget.rb"))
      .to include("class Admin::Gadget < Phlex::HTML")
      .and include('div(id: "admin_gadget")')
    expect_valid_generated_sources(@destination)
  end
end
