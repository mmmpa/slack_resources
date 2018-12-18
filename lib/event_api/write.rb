require 'pathname'
require 'rest-client'
require 'nokogiri'
require 'json'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/string/inflections'

BASE_DIR = Pathname('./resources/event_api/')
EXAMPLES_DIR = BASE_DIR.join('examples')
ADDED_EXAMPLES_DIR = BASE_DIR.join('_added_examples')
DETAILS_DIR = BASE_DIR.join('details')
SCHEMAS_DIR = BASE_DIR.join('schemas')

FileUtils.mkdir_p(DETAILS_DIR)
FileUtils.mkdir_p(SCHEMAS_DIR)

PRESET_SCHEMA = JSON.parse(File.read('lib/schema.json'))
PRESET_DEFINITIONS = PRESET_SCHEMA['definitions']

class Hash
  def protect_merge!(b)
    (b.keys - keys).map do |new_key|
      self[new_key] = b[new_key]
    end

    self
  end

  def key_ordered
    keys.sort.inject({}) do |a, k|
      a.merge!(k => self[k])
    end
  end
end

def to_schema(response, url, preset_schema = JSON.parse(PRESET_SCHEMA.to_json))
  schema, defined, defined_used = to_schema_support(response, url, 'root', preset_schema)

  [schema, defined, defined_used]
end

def string_k_v(k, v)
  (v.nil? || v.is_a?(String)) && k
end

def to_schema_support(response, url, key = 'root', preset = {}, defined = {}, defined_used = [], parent = {})
  types = JSON.parse(response.to_json).key_ordered

  def_string = ->(id_key) { id_key.tap { defined.merge!(id_key => { "type" => "string" }) } }

  properties = types.inject({}) do |a, (k, v)|
    if v.is_a?(Hash)
      if v['_type'] && v['_type'] == 'enum'
        def_k = "#{key == 'root' ? types['type'] : key}_#{k}"
        defined.merge!(def_k => { 'type' => 'string', enum: v['items'] })
        next a.merge(k => { "$ref" => "#/definitions/#{def_k}" })
      end

      def_k =
        case
        when k == 'item'
          t = types['type'].split('_').shift
          "#{t}_item"
        else
          k
        end

      schema, _ = to_schema_support(v, url, k, preset, defined, defined_used, types)
      defined_used << def_k
      defined.merge!(def_k => schema)
      next a.merge(k => { "$ref" => "#/definitions/#{def_k}" })
    end

    type =
      case k
      when key == 'root' && 'type'
        { 'const' => v }
      when key == 'root' && 'subtype'
        def_string.('subscription_subtype')
      when key == 'event' && 'type'
        { 'const' => v }
      when key == 'item' && 'type'
        t = parent['type'].split('_').shift
        def_string.("#{t}_#{key}_type")
      when 'type'
        def_string.("#{key}_type")


      when 'name'
        def_string.("#{key}_name")
      when 'id'
        def_string.("#{key}_id")
      when /.+_id$/
        def_string.(k)

      when types['type'] == 'emoji_changed' && 'names'
        def_string.('emoji_name')
        '[]emoji_name'
      when 'reaction'
        def_string.('emoji_name')
        'emoji_name'
      when types['type'] == 'team_rename' && 'name'
        'team_name'

      when string_k_v('item_user', v),
        string_k_v('user', v),
        string_k_v('creator', v),
        string_k_v('inviter', v),
        string_k_v('created_by', v),
        string_k_v('updated_by', v),
        string_k_v('deleted_by', v)
        def_string.('user_id')
      when string_k_v('channel', v)
        def_string.('channel_id')
      when string_k_v('comment', v)
        def_string.('comment_id')
      when string_k_v('team', v)
        def_string.('team_id')

      when 'authed_users', 'authed_users', 'users', 'added_users', 'removed_users'
        def_string.('user_id')
        '[]user_id'
      when 'authed_teams'
        def_string.('team_id')
        '[]team_id'
      when 'channels'
        def_string.('channel_id')
        '[]channel_id'
      when 'groups'
        def_string.('group_id')
        '[]group_id'

      when 'scopes'
        '[]scope'
      when 'links'
        '[]link'

      when 'user_count', 'added_users_count', 'removed_users_count'
        'user_count'

      when 'resources'
        defined.merge!('resource_item' => to_schema_support(v.first, url, k, preset, defined, defined_used, types))
        '[]resource_item'

      when v.is_a?(Integer) && k
        'time_integer'
      when (v == true || v == false) && k
        'boolean'
      when 'email_domain', 'text', 'description', 'handle', 'url', 'domain'
        'string'
      when parent['type'] == 'tokens_revoked' && 'oauth'
        '[]string'
      when parent['type'] == 'tokens_revoked' && 'bot'
        '[]string'
      when 'latest', /.+_ts$/
        'timestamp'
      when preset[k] && k
        k
      else
        if v.respond_to?(:to_f) && v == v.to_f.to_s
          'timestamp'
        elsif v.is_a?(String)
          def_string.(k)
          'string'
        else
          v
        end
      end

    if default_type?(type)
      a.merge(k => { "type" => type })
    elsif type.is_a?(Hash)
      a.merge(k => type)
    elsif type && type[0..1] == '[]'
      item = type[2..-1]
      if default_type?(item)
        next a.merge(
          k => {
            "type" => 'array',
            'items' => {
              "type" => item
            }
          }
        )
      else
        if v.first.is_a?(Hash)
          schema, _ = to_schema_support(v.first, url, item, preset, defined, defined_used, types)
          defined.merge!(item => schema)
        elsif v.first.is_a?(String)
          def_string.(item)
        end

        defined_used << item
      end
      a.merge(
        k => {
          "type" => 'array',
          'items' => {
            "$ref" => "#/definitions/#{item}"
          }
        }
      )
    else
      defined_used << type
      a.merge(
        k => {
          "$ref" => "#/definitions/#{type}"
        }
      )
    end
  end

  [
    {
      "type" => "object",
      description: properties.blank? ? "definition snipped. learn more: #{url}" : '(defined by script)',
      "properties" => properties
    },
    defined,
    defined_used,
  ]
end

def default_type?(type)
  type == 'string' || type == 'number' || type == 'object' || type == 'array' || type == 'boolean' || type == 'null'
end

def safe_merge(a, b)
  (b.keys - a.keys).map do |new_key|
    a[new_key] = b[new_key]
  end

  a
end

def prepare_data
  Dir.glob(ADDED_EXAMPLES_DIR.join('**/*.json')).each do |f|
    file_name = File.basename(f)
    FileUtils.copy(f, EXAMPLES_DIR.join(file_name))
  end

  raw_examples = Dir.glob(EXAMPLES_DIR.join('**/*.json')).map do |f|
    example = JSON.parse(File.read(f))
    (example['event'].presence || example).key_ordered
  end

  raw_examples.inject({}) do |a, v|
    type = v['type']
    unless a[type]
      next a.merge!(type => v)
    end

    already = a[type]

    keys = (already.keys + v.keys).uniq

    keys.each do |k|
      vv = v[k]
      pre_v = already[k]

      if k.match('.*_type')
        if pre_v.is_a?(Hash) && pre_v['_type'] == 'enum'
          pre_v['items'] << vv
        else
          already[k] = {
            '_type' => 'enum',
            'target' => k,
            'items' => [pre_v],
          }
        end
      else
        # TODO: nil が許容されている場合は type を or にする
      end
    end

    a
  end
end

def write_event_api_summary


  meta = JSON.parse(File.read(BASE_DIR.join('meta.json')))

  event_api_pages = prepare_data.map do |type, data|
    info = meta['subscriptions'][type] || {}
    [info['url'], type, data, info['compatibility'], info['scopes']]
  end

  preset = PRESET_DEFINITIONS.merge(
    'subscription_type' => {
      "type": "string",
      "enum": meta['types'],
    },
    'scope' => {
      "type": "string",
      "enum": meta['scopes'],
    }
  )

  all_defined = JSON.parse(preset.to_json)
  all_schema = {}

  all_details = event_api_pages.map do |url, type, response, compatibility, scopes|
    schema, defined, used = to_schema(response, url, preset)
    schema.merge!(description: "learn more: #{url}")

    pre = preset.protect_merge!(defined)

    all_defined.protect_merge!(defined)

    base = used.uniq.inject({}) do |a, pre_key|
      pre[pre_key] ? a.protect_merge!(pre_key => pre[pre_key]) : a
    end

    normalized_response = response.inject({}) do |a, (k, v)|
      unless (v.is_a?(Hash) && v['_type'] == 'enum')
        next a.protect_merge!(k => v)
      end

      a.merge!(v['target'] => v['items'].map{ |s| s ? s : 'null' }.join('|'))
    end

    {
      url: url,
      type: type,
      response: normalized_response,
      defined: base.protect_merge!(defined),
      schema: schema.protect_merge!(example: normalized_response),
      compatibility: compatibility,
      scopes: scopes,
    }
  end

  all_details.map do |data|
    type = data[:type]
    schema = data[:schema]
    defined = data.delete(:defined)

    all_schema[type] = schema

    schema_data = {
      "$schema": "http://json-schema.org/draft-07/schema",
      "definitions" => defined.protect_merge!(type => schema)
    }

    data[:schema] = schema_data

    File.write(SCHEMAS_DIR.join("#{type}.json").to_s, JSON.pretty_generate(schema_data))
    File.write(DETAILS_DIR.join("#{type}.json").to_s, JSON.pretty_generate(data))
  end

  File.write(BASE_DIR.join('schema.json').to_s, JSON.pretty_generate({
    "$schema": "http://json-schema.org/draft-07/schema",
    "definitions" => all_defined.protect_merge!(all_schema).key_ordered
  }))
  File.write(BASE_DIR.join('summary.json').to_s, JSON.pretty_generate(all_details))
end

write_event_api_summary
