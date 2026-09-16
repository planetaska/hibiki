# frozen_string_literal: true

require "yaml"

# The Agent Skills under skills/ are hand-written digests of docs/, so nothing
# regenerates them. This check is what keeps them honest: frontmatter per the
# agentskills.io spec, every link resolvable, and the version facts in their
# metadata equal to what the gems and the docs say right now.
class SkillsCheck
  ROOT = File.expand_path("..", __dir__)
  SKILLS = File.join(ROOT, "skills")
  DOCS_URL = "https://planetaska.github.io/hibiki/"
  SPEC_KEYS = %w[name description license compatibility metadata allowed-tools].freeze
  NAME = /\A[a-z0-9]+(-[a-z0-9]+)*\z/
  # hibiki_phlex is a sibling repo, not on this load path; bump by hand.
  HIBIKI_PHLEX_VERSION = "0.1.0"

  def initialize
    @errors = []
  end

  def run
    skill_dirs.each { |dir| check_skill(dir) }
    return if @errors.empty?

    abort(["skills:check found #{@errors.size} problem(s):", *@errors.map { |e| "  #{e}" }].join("\n"))
  end

  private

  def skill_dirs = Dir[File.join(SKILLS, "*", "SKILL.md")].map { |f| File.dirname(f) }.sort

  def error(file, message) = @errors << "#{file.delete_prefix("#{ROOT}/")}: #{message}"

  def check_skill(dir)
    skill = File.join(dir, "SKILL.md")
    front, body = split_frontmatter(skill)
    return error(skill, "no YAML frontmatter") unless front

    check_frontmatter(skill, File.basename(dir), front)
    check_body_length(skill, body)
    Dir[File.join(dir, "**", "*.md")].each { |page| check_links(dir, page) }
    Dir[File.join(dir, "references", "*.md")].each { |ref| check_full_docs_line(ref) }
  end

  def check_body_length(skill, body)
    lines = body.lines.size
    error(skill, "body is #{lines} lines; keep it under 500") if lines >= 500
  end

  def split_frontmatter(file)
    text = File.read(file, encoding: "UTF-8")
    match = text.match(/\A---\n(.*?)\n---\n(.*)\z/m)
    return nil unless match

    [YAML.safe_load(match[1]), match[2]]
  rescue Psych::SyntaxError => e
    error(file, "frontmatter does not parse: #{e.message}")
    nil
  end

  def check_frontmatter(file, dirname, front)
    (front.keys - SPEC_KEYS).each { |key| error(file, "`#{key}` is not an agentskills.io frontmatter field") }
    check_name(file, dirname, front["name"])
    check_description(file, front["description"])
    check_metadata(file, front["metadata"])
  end

  def check_name(file, dirname, name)
    error(file, "name `#{name}` must equal the directory name `#{dirname}`") unless name == dirname
    error(file, "name `#{name}` must be lowercase words joined by single hyphens") unless name.to_s.match?(NAME)
    error(file, "name is longer than 64 characters") if name.to_s.length > 64
  end

  def check_description(file, description)
    return error(file, "description is missing") if description.to_s.strip.empty?

    length = description.length
    error(file, "description is #{length} characters; the spec caps it at 1024") if length > 1024
  end

  def check_metadata(file, metadata)
    return error(file, "metadata is missing") unless metadata.is_a?(Hash)

    metadata.each { |k, v| error(file, "metadata.#{k} must be a string") unless v.is_a?(String) }
    expected_versions.each do |key, version|
      next if metadata[key] == version

      error(file, "metadata.#{key} is #{metadata[key].inspect}; the current release is #{version}")
    end
  end

  def expected_versions
    @expected_versions ||= {
      "hibiki" => hibiki_version,
      "hibiki_rails" => hibiki_rails_version,
      "hibiki_phlex" => HIBIKI_PHLEX_VERSION
    }
  end

  def hibiki_version
    require File.join(ROOT, "lib", "hibiki", "version")
    Hibiki::VERSION
  end

  # The newest row of the docs' lockstep table is the release the docs
  # describe, which is what the skills must describe too.
  def hibiki_rails_version
    table = File.read(File.join(ROOT, "docs", "_ref_rails", "version-lockstep.md"), encoding: "UTF-8")
    table[/^\|\s*(\d+\.\d+\.\d+)\s*\|/, 1] or raise "no version row in version-lockstep.md"
  end

  def check_links(dir, page)
    File.read(page, encoding: "UTF-8").scan(/\]\(([^)\s#]+)(?:#[^)]*)?\)/).flatten.each do |target|
      next if target.match?(/\A[a-z]+:/)

      path = File.expand_path(target, File.dirname(page))
      error(page, "link `#{target}` leaves the skill directory") unless path.start_with?("#{dir}/")
      error(page, "link `#{target}` does not resolve") unless File.exist?(path)
    end
  end

  def check_full_docs_line(ref)
    lines = File.read(ref, encoding: "UTF-8").lines.map(&:chomp).reject(&:empty?)
    unless lines.last.to_s.start_with?("Full docs: #{DOCS_URL}")
      return error(ref, "last line must be `Full docs: #{DOCS_URL}<stem>/`")
    end

    lines.grep(/\A(Full docs|See also): /).each { |line| check_docs_slug(ref, line) }
  end

  def check_docs_slug(ref, line)
    slug = line[%r{#{Regexp.escape(DOCS_URL)}([a-z0-9-]+)/}, 1]
    return error(ref, "`#{line}` is not a docs page URL") unless slug
    return if Dir[File.join(ROOT, "docs", "_*", "#{slug}.md")].any?

    error(ref, "`#{slug}` is not a page under docs/")
  end
end

namespace :skills do
  desc "Validate the Agent Skills under skills/ (frontmatter, links, version facts)"
  task(:check) { SkillsCheck.new.run }
end
