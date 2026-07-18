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

  # The stock Rails 8 importmap app shapes both files start in.
  def seed_stock_app
    FileUtils.mkdir_p(File.dirname(index_js))
    File.write(index_js, <<~JS)
      import { application } from "controllers/application"
      import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
      eagerLoadControllersFrom("controllers", application)
    JS
    FileUtils.mkdir_p(File.dirname(application_helper))
    File.write(application_helper, "module ApplicationHelper\nend\n")
  end

  it "registers the packaged controller and includes the helpers" do
    seed_stock_app
    run_generator(described_class, destination: @destination)

    expect(File.read(index_js)).to include('import HibikiController from "hibiki"')
      .and include('application.register("hibiki", HibikiController)')
    expect(File.read(application_helper))
      .to include("module ApplicationHelper\n  include Hibiki::Rails::Helpers\nend")
  end

  it "is idempotent: a second run changes nothing" do
    seed_stock_app
    run_generator(described_class, destination: @destination)
    output = run_generator(described_class, destination: @destination)

    expect(output).to include("identical")
    expect(File.read(index_js).scan('application.register("hibiki"').count).to eq(1)
    expect(File.read(application_helper).scan("Hibiki::Rails::Helpers").count).to eq(1)
  end

  it "prints manual instructions when the wiring targets are missing" do
    output = run_generator(described_class, destination: @destination)

    expect(output).to include("add this yourself")
    expect(output).to include('application.register("hibiki", HibikiController)')
    expect(output).to include("include Hibiki::Rails::Helpers")
    expect(File.exist?(index_js)).to be(false)
  end
end
