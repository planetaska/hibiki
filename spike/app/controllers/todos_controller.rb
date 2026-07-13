# frozen_string_literal: true

class TodosController < ApplicationController
  def show
    @cid = SecureRandom.uuid
  end
end
