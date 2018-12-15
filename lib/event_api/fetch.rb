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
  responce_raw = doc.css('#api_main_content pre')[0].content
  parse(responce_raw)
end

def pick_compatibility(doc)
  doc.css('#api_main_content .col.span_2_of_3.small')[0].content.gsub("\t\t", "\t").split("\t").select(&:present?)[1..-1] || []
end

def pick_scopes(doc)
  doc.css('#api_main_content .col.span_1_of_3.small')[0]&.content.gsub("\t\t", "\t").split("\t").select(&:present?)[1..-1] || []
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
  urls = {}
  event_api_pages.each do |url, type, page|
    responce, compatibility, scopes = analise(page)
    urls[type] = {
      url: url,
      compatibility: compatibility,
      scopes: scopes,
    }
    File.write(EXAMPLES_DIR.join("#{type}.json"), JSON.pretty_generate(responce))
  end

  File.write(BASE_DIR.join("meta.json"), JSON.pretty_generate(urls))
end

write_response_sample
