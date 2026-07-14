# frozen_string_literal: true

require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
# The root .rubocop.yml excludes hibiki_phlex/**/* (this gem lints itself),
# and RuboCop merges the repo-root AllCops/Exclude into subdirectory runs —
# --ignore-parent-exclusion is the flag made for exactly this layout.
RuboCop::RakeTask.new(:rubocop) do |task|
  task.options = ["--ignore-parent-exclusion"]
end

task default: %i[spec rubocop]
