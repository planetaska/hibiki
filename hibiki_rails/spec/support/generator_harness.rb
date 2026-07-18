# frozen_string_literal: true

require "rails/generators"

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
end
