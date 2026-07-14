# frozen_string_literal: true

require "spec_helper"

RSpec.describe Hibiki::Rails::Helpers do
  # The helpers are opt-in instance methods, exactly like Hibiki::DSL.
  let(:view) { Class.new { include Hibiki::Rails::Helpers }.new }

  describe "#hibiki_island" do
    it "stamps the controller, channel, and cid as Stimulus values" do
      expect(view.hibiki_island("CounterChannel", cid: "abc")).to eq(
        { data: { controller: "hibiki",
                  hibiki_channel_value: "CounterChannel",
                  hibiki_cid_value: "abc" } }
      )
    end

    it "accepts the channel class itself" do
      stub_const("TodosChannel", Class.new)
      data = view.hibiki_island(TodosChannel, cid: "abc")[:data]
      expect(data[:hibiki_channel_value]).to eq("TodosChannel")
    end
  end

  describe "#on" do
    it "defaults to the click event" do
      expect(view.on(:increment)).to eq({ data: { hibiki_on: "click->increment" } })
    end

    it "encodes the chosen event into the token" do
      expect(view.on(:set_step, event: :change)[:data][:hibiki_on])
        .to eq("change->set_step")
      expect(view.on(:add, event: :submit)[:data][:hibiki_on])
        .to eq("submit->add")
    end

    it "serializes with: as a JSON payload attribute" do
      expect(view.on(:toggle, with: { index: 3 })[:data]).to eq(
        { hibiki_on: "click->toggle", hibiki_with: '{"index":3}' }
      )
    end

    it "omits the payload attribute when with: is absent" do
      expect(view.on(:increment)[:data]).not_to have_key(:hibiki_with)
    end
  end
end
