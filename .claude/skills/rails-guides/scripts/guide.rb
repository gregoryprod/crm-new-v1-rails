#!/usr/bin/env ruby
# frozen_string_literal: true

# Prints one section of the official Rails guide for the Rails version this app uses.
#
#   ruby guide.rb --index                  guide names of this Rails version
#   ruby guide.rb <guide>                  the guide's headings with line numbers
#   ruby guide.rb <guide> "<heading>"      only that section (case-insensitive, backticks ignored)
#
# Guides come from github.com/rails/rails at the exact version tag (CC BY-SA 4.0). They are
# cached in the system temp directory and never copied into the repository.
require "net/http"
require "fileutils"
require "tmpdir"

def root
  dir = Dir.pwd
  dir = File.dirname(dir) until File.exist?(File.join(dir, "Gemfile.lock")) || File.dirname(dir) == dir
  dir
end

def rails_version
  ENV["RAILS_GUIDES_VERSION"] || File.read(File.join(root, "Gemfile.lock"))[/^    rails \(([\d.]+)\)$/, 1] ||
    abort("Rails version not found in Gemfile.lock; set RAILS_GUIDES_VERSION")
end

def fetch(name)
  version = rails_version
  path = File.join(Dir.tmpdir, "rails-guides", version, name)
  return File.read(path, encoding: "UTF-8") if File.size?(path)
  uri = URI("https://raw.githubusercontent.com/rails/rails/v#{version}/guides/source/#{name}")
  response = Net::HTTP.get_response(uri)
  abort("No #{name} in Rails #{version} (try --index)") unless response.is_a?(Net::HTTPSuccess)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, response.body.force_encoding("UTF-8"))
  response.body
end

# Rails guides mix "## ATX" headings with setext ones ("Title" over "-----"/"====="):
# return [line_number, level, text] for each heading outside code fences.
def headings(lines)
  fence = false
  result = []
  lines.each_with_index do |line, i|
    fence = !fence if line.start_with?("```")
    next if fence
    if (m = line.match(/\A(\#{1,6}) (.+)/))
      result << [ i, m[1].length, m[2].strip ]
    elsif line.strip != "" && (nxt = lines[i + 1]) && nxt.match?(/\A(-{3,}|={3,})\s*\z/) && !line.match?(/\A[-=\s]+\z/)
      result << [ i, nxt.start_with?("=") ? 1 : 2, line.strip ]
    end
  end
  result
end

def plain(text) = text.delete("`").downcase

command = ARGV[0] or abort("usage: ruby guide.rb --index | <guide> [\"heading\"]")

if command == "--index"
  puts fetch("documents.yaml").scan(/^ +url: ([a-z0-9_]+)\.html$/).flatten
  exit
end

name = command.delete_suffix(".md")
lines = fetch("#{name}.md").lines(chomp: true)
heads = headings(lines)

if ARGV[1].nil?
  puts "# Rails #{rails_version} guide: #{name} (#{lines.length} lines)"
  heads.each { |i, level, text| puts "#{i + 1}: #{'  ' * (level - 1)}#{text}" }
  exit
end

pattern = Regexp.new(Regexp.escape(plain(ARGV[1])))
start = heads.find { |_, _, text| plain(text).match?(pattern) } or abort("No heading matching #{ARGV[1].inspect} in #{name}")
finish = heads.find { |i, level, _| i > start[0] && level <= start[1] }
puts lines[start[0]...(finish ? finish[0] : lines.length)]
