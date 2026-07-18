# frozen_string_literal: true

require "rails/generators"
require "erubi"

# The generators are found by Rails via $LOAD_PATH at runtime; specs load
# them all up front the same way a `bin/rails g` invocation would.
Dir[File.expand_path("../../lib/generators/**/*_generator.rb", __dir__)].each { |file| require file }

module GeneratorHarness
  # Run a generator class against a throwaway destination root, returning
  # everything it printed (say/say_status write to $stdout via Thor's
  # shell, resolved at call time — capturing here is enough).
  def run_generator(klass, args = [], destination:)
    output = StringIO.new
    original = $stdout
    $stdout = output
    klass.start(args, destination_root: destination)
    output.string
  ensure
    $stdout = original
  end

  # Syntax smoke over everything a generator emitted: compile (never run)
  # each Ruby file directly and each ERB view through ActionView's erubi
  # subclass (plain Erubi::Engine can't parse Rails' `<%= tag.div do %>`
  # block-expression form) — a SyntaxError in any template fails the
  # example.
  def expect_valid_generated_sources(destination)
    Dir[File.join(destination, "**/*.rb")].each do |path|
      RubyVM::InstructionSequence.compile(File.read(path), path)
    end
    Dir[File.join(destination, "**/*.erb")].each do |path|
      src = ActionView::Template::Handlers::ERB::Erubi.new(File.read(path)).src
      RubyVM::InstructionSequence.compile(src, path)
    end
  end
end
