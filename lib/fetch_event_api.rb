require 'pathname'
require 'rest-client'
require 'nokogiri'
require 'json'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/string/inflections'

BASE_DIR = Pathname('./resources/event_api/')
FileUtils.mkdir_p(BASE_DIR)
FileUtils.mkdir_p(BASE_DIR.join('responses'))
FileUtils.mkdir_p(BASE_DIR.join('details'))

PRESET_SCHEMA = JSON.parse(File.read('lib/schema.json'))

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

def to_schema(responce, preset_schema = JSON.parse(PRESET_SCHEMA.to_json))
  schema, defined, defined_used = to_schema_support(responce, 'root', preset_schema)

  [schema, defined, defined_used]
end

def to_schema_support(responce, key = 'root', preset = {}, defined = {}, defined_used = [], parent = {})
  types = JSON.parse(responce.to_json)

  return key.camelize if responce.blank?

  properties = types.inject({}) do |a, (k, v)|
    if v.is_a?(Hash)
      if !v.blank?
        k = if k == 'item'
              if types['type'].match(/reaction_.+/)
                'reaction_item'
              else
                'item'
              end
            elsif types['type'] == 'event_callback' && k == 'event'
              "#{v['type']}_event"
            else
              k
            end


        schema, _ = to_schema_support(v, k, preset, defined, defined_used, types)
        defined.merge!(k => schema)
        next a.merge(k => { "$ref" => "#/definitions/core/#{k}" })
      elsif responce['type']
        nested_key = "#{responce['type'].split('_').shift}_#{k}"
        next a.merge(nested_key => { "$ref" => "#/definitions/core/#{nested_key}" })
      else
        next a.merge(k => { "$ref" => "#/definitions/core/#{k}" })
      end
    end

    type =
      case k
      when key == 'root' && 'type'
        'response_type'
      when key == 'root' && 'subtype'
        'response_subtype'
      when key == 'event' && 'type'
        'event_type'
      when key.match(/.+_event$/) && 'type'
        'event_type'
      when key == 'resource' && 'type'
        'resource_type'
      when key == 'grant' && 'type'
        'grant_type'
      when key == 'channel' && 'id'
        'channel_id'
      when key == 'file' && 'id'
        'file_id'
      when key == 'channel' && 'name'
        'channel_name'
      when key == 'channel' && 'name'
        'channel_name'
      when key == 'subteam' && 'name'
        'subteam_name'
      when key == 'subteam' && 'id'
        'subteam_id'
      when key == 'link_shared_event' && 'links'
        '[]link'
      when parent['type'].to_s.split('_').shift == 'reaction' && 'type'
        'reaction_item_type'

      when types['type'] == 'emoji_changed' && 'names'
        '[]emoji_name'
      when types['type'] == 'team_rename' && 'name'
        'team_name'

      when v.is_a?(String) && 'item_user'
        'user_id'
      when v.is_a?(String) && 'user'
        'user_id'
      when v.is_a?(String) && 'creator'
        'user_id'
      when v.is_a?(String) && 'channel'
        'channel_id'
      when v.is_a?(String) && 'comment'
        'comment_id'
      when v.is_a?(String) && 'team'
        'team_id'
      when v.is_a?(String) && 'inviter'
        'user_id'
      when v.is_a?(String) && 'created_by'
        'user_id'
      when v.is_a?(String) && 'updated_by'
        'user_id'

      when 'authed_users'
        '[]user_id'
      when 'authed_users'
        '[]user_id'
      when 'users'
        '[]user_id'
      when 'added_users'
        '[]user_id'
      when 'removed_users'
        '[]user_id'
      when 'authed_teams'
        '[]team_id'
      when 'user_count'
        'user_count'
      when 'added_users_count'
        'user_count'
      when 'file_id'
        'file_id'
      when 'removed_users_count'
        'user_count'
      when 'auto_type'
        'auto_type'
      when 'scopes'
        '[]scope'
      when 'channels'
        '[]channel_id'
      when 'groups'
        '[]group_id'
      when 'resources'
        defined.merge!('resource_item' => to_schema_support(v.first, k, preset, defined, defined_used, types))
        '[]resource_item'

      when 'deleted_by'
        'user_id'
      when v.is_a?(Integer) && k
        'time_integer'
      when (v == true || v == false) && k
        'boolean'
      when 'reaction'
        'emoji_name'
      when 'token'
        'token'
      when 'email_domain'
        'string'
      when 'text'
        'string'
      when 'description'
        'string'
      when 'handle'
        'string'
      when 'url'
        'string'
      when 'domain'
        'string'
      when parent['type'] == 'tokens_revoked' && 'oauth'
        '[]string'
      when parent['type'] == 'tokens_revoked' && 'bot'
        '[]string'
      when 'channel_type'
        'channel_type'
      when 'challenge'
        'challenge'
      when 'latest'
        'timestamp'
      when /.+_ts$/
        'timestamp'
      when /.+_id$/
        defined.merge!(k => { "type" => "string" })
        k
      else
        if v.respond_to?(:to_f) && v == v.to_f.to_s
          'timestamp'
        else
          v
        end
      end

    if default_type?(type)
      a.merge(k => { "type" => type })
    elsif type && type[0..1] == '[]'
      item = type[2..-1]
      unless default_type?(item)
        if v.first.is_a?(Hash)
          schema, _ = to_schema_support(v.first, item, preset, defined, defined_used, types)
          defined.merge!(item => schema)
        end
        defined_used << item
      end
      a.merge(
        k => {
          "type" => 'array',
          'items' => {
            "$ref" => "#/definitions/core/#{item}"
          }
        }
      )
    else
      defined_used << type
      a.merge(
        k => {
          "$ref" => "#/definitions/core/#{type}"
        }
      )
    end
  end

  [
    {
      "type" => "object",
      "properties" => properties
    },
    defined,
    defined_used,
  ]
end

def default_type?(type)
  type == 'string' || type == 'number' || type == 'object' || type == 'array' || type == 'boolean' || type == 'null'
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

def write_event_api_summary
  path = BASE_DIR.join('details')

  data = event_api_pages.map do |url, type, page|
    responce, compatibility, scopes = analise(page)
    schema, defined, used = to_schema(responce)

    # pp type, defined

    base = used.uniq.inject({}) do |a, preset|
      a.merge!(preset => PRESET_SCHEMA['definitions'][preset])
    end

    {
      url: url,
      type: type,
      responce: responce,
      schema: {
        "$schema": "http://json-schema.org/draft-04/schema",
        "definitions" => {
          core: {
            "definitions" => base.merge(defined)
          },
          event_api_subscription: {
            "definitions" => {
              type => schema
            }
          }
        }
      },
      compatibility: compatibility,
      scopes: scopes,
    }.tap do |data|
      File.write(path.join("#{type}.json").to_s, JSON.pretty_generate(data))
    end
  end

  File.write(BASE_DIR.join('summary.json').to_s, JSON.pretty_generate(data))
end

def write_response_sample
  dist = BASE_DIR.join('responses')
  FileUtils.mkdir_p(dist)

  event_api_pages.each do |_, type, page|
    responce, _, _ = analise(page)
    File.write(dist.join("#{type}.json"), JSON.pretty_generate(responce))
  end
end

write_response_sample
write_event_api_summary
