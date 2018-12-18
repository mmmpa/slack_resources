require 'pathname'
require 'rest-client'
require 'nokogiri'
require 'json'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/string/inflections'

BASE_DIR = Pathname('./resources/event_api')
EXAMPLES_DIR = BASE_DIR.join('examples')
FileUtils.mkdir_p(EXAMPLES_DIR)

def fetch(url)
  tmp = Pathname('./tmp')
  path = tmp.join(url.gsub(':', '_').gsub('/', '_')).to_s

  if File.exist?(path)
    return File.read(path)
  end

  RestClient.get(url).tap { |data| File.write(path, data) }
end

def event_api_urls
  base = 'https://api.slack.com/events/api'
  doc = Nokogiri.parse(fetch(base))
  doc.css('#api_main_content a.bold.block').map { |a| URI.join(base, a.attributes['href']).to_s }
end

def event_api_pages
  @event_api_pages ||= event_api_urls.map do |url|
    [url, url.split('/').pop, fetch(url)]
  end
end

def analise(html)
  doc = Nokogiri.parse(html)
  [
    pick_response(doc),
    pick_compatibility(doc),
    pick_scopes(doc),
  ]
end

def pick_response(doc)
  response_raw = doc.css('#api_main_content pre')[0].content
  parse(response_raw)
end

def pick_compatibility(doc)
  doc.css('#api_main_content .col.span_2_of_3.small')[0].
    content.
    gsub("\t\t", "\t").
    split("\t").
    select(&:present?)[1..-1]&.
    map(&:chomp) || []
end

def pick_scopes(doc)
  doc.css('#api_main_content .col.span_1_of_3.small')[0]&.
    content.
    gsub("\t\t", "\t").
    split("\t").
    select(&:present?)[1..-1]&.
    map(&:chomp) || []
end

def parse(json)
  clean = json.gsub(%r[\{[\s\n]*…[^}]*\},?]m, '{},').gsub(%r[\{[\s\n]*\.\.\.[^}]*\},?]m, '{},').gsub(%{"3"\n}, %{"3",\n})
  JSON.parse(clean)
rescue
  force(clean)
end

def force(clean)
  eval(clean)
rescue
  raise
end

def write_response_sample
  types = []
  on_event_api = []
  on_rtm = []
  all_scopes = []
  subscriptions = {}

  event_api_pages.each do |url, type, page|
    response, compatibility, scopes = analise(page)

    types << type
    on_event_api << type if compatibility.include?('Events API')
    on_rtm << type if compatibility.include?('RTM')

    all_scopes += scopes

    subscriptions[type] = {
      url: url,
      compatibility: compatibility,
      scopes: scopes,
    }
    File.write(EXAMPLES_DIR.join("#{type}.json"), JSON.pretty_generate(response))
  end

  File.write(BASE_DIR.join("meta.json"), JSON.pretty_generate({
    types: types.uniq,
    on_event_api: on_event_api.uniq,
    on_rtm: on_rtm.uniq,
    scopes: all_scopes.uniq,
    subscriptions: subscriptions,
  }))
end

write_response_sample
