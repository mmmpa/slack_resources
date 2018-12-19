require 'pathname'
require 'rest-client'
require 'nokogiri'
require 'json'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/string/inflections'

module StrongHash
  refine Hash do
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
end

class Writer
  using StrongHash

  def initialize(dir: './tmp')
    @base_dir = Pathname(dir)
    @examples_dir = @base_dir.join('examples')
    @added_examples_dir = @base_dir.join('_added_examples')
    @details_dir = @base_dir.join('details')
    @schemas_dir = @base_dir.join('schemas')
    @preset_schema = JSON.parse(File.read('lib/schema.json'))
    @preset_definitions = @preset_schema['definitions']
  end

  def execute!
    FileUtils.mkdir_p(@details_dir)
    FileUtils.mkdir_p(@schemas_dir)

    write_event_api_summary
  end

# @base_dir = Pathname('./lib/slack_resources/resources/event_api/')


  def to_schema(response, url, preset_schema = JSON.parse(@preset_schema.to_json))
    schema, defined, defined_used = to_schema_support(response, url, 'root', preset_schema)

    [schema, defined, defined_used]
  end

  def string_k_v(k, v)
    (v.nil? || v.is_a?(String)) && k
  end

  def to_schema_support(response, url, key = 'root', preset = {}, defined = {}, defined_used = [], parent = {})
    types = JSON.parse(response.to_json).key_ordered

    def_string = ->(id_key) { id_key.tap { defined.merge!(id_key => { 'type' => 'string' }) } }

    properties = types.inject({}) do |a, (k, v)|
      if v.is_a?(Hash)
        if v['_type'] && v['_type'] == 'enum'
          def_k = "#{key == 'root' ? types['type'] : key}_#{k}"
          defined[def_k] = { 'type' => 'string', enum: v['items'] }
          next a.merge(k => { '$ref' => "#/definitions/#{def_k}" })
        end

        def_k =
          case
          when k == 'item'
            t = types['type'].split('_').shift
            "#{t}_item"
          else
            k
          end

        schema, = to_schema_support(v, url, k, preset, defined, defined_used, types)
        defined_used << def_k
        defined[def_k] = schema
        next a.merge(k => { '$ref' => "#/definitions/#{def_k}" })
      end

      type =
        case k
        when key == 'root' && 'type'
          { 'const' => v }
        when key == 'root' && 'subtype'
          def_string.call('subscription_subtype')
        when key == 'event' && 'type'
          { 'const' => v }
        when key == 'item' && 'type'
          t = parent['type'].split('_').shift
          def_string.call("#{t}_#{key}_type")
        when 'type'
          def_string.call("#{key}_type")

        when 'name'
          def_string.call("#{key}_name")
        when 'id'
          def_string.call("#{key}_id")
        when /.+_id$/
          def_string.call(k)

        when types['type'] == 'emoji_changed' && 'names'
          def_string.call('emoji_name')
          '[]emoji_name'
        when 'reaction'
          def_string.call('emoji_name')
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
          def_string.call('user_id')
        when string_k_v('channel', v)
          def_string.call('channel_id')
        when string_k_v('comment', v)
          def_string.call('comment_id')
        when string_k_v('team', v)
          def_string.call('team_id')

        when 'authed_users', 'authed_users', 'users', 'added_users', 'removed_users'
          def_string.call('user_id')
          '[]user_id'
        when 'authed_teams'
          def_string.call('team_id')
          '[]team_id'
        when 'channels'
          def_string.call('channel_id')
          '[]channel_id'
        when 'groups'
          def_string.call('group_id')
          '[]group_id'

        when 'scopes'
          '[]scope'
        when 'links'
          '[]link'

        when 'user_count', 'added_users_count', 'removed_users_count'
          'user_count'

        when 'resources'
          defined['resource_item'] = to_schema_support(v.first, url, k, preset, defined, defined_used, types)
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
            def_string.call(k)
            'string'
          else
            v
          end
        end

      if default_type?(type)
        a.merge(k => { 'type' => type })
      elsif type.is_a?(Hash)
        a.merge(k => type)
      elsif type && type[0..1] == '[]'
        item = type[2..-1]
        if default_type?(item)
          next a.merge(
            k => {
              'type' => 'array',
              'items' => {
                'type' => item,
              },
            }
          )
        else
          if v.first.is_a?(Hash)
            schema, = to_schema_support(v.first, url, item, preset, defined, defined_used, types)
            defined[item] = schema
          elsif v.first.is_a?(String)
            def_string.call(item)
          end

          defined_used << item
        end
        a.merge(
          k => {
            'type' => 'array',
            'items' => {
              '$ref' => "#/definitions/#{item}",
            },
          }
        )
      else
        defined_used << type
        a.merge(
          k => {
            '$ref' => "#/definitions/#{type}",
          }
        )
      end
    end

    [
      {
        'type' => 'object',
        description: properties.blank? ? "definition snipped. learn more: #{url}" : '(defined by script)',
        'properties' => properties,
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

  def prepared_data
    ExamplePreparation.new(
      examples_dir: @examples_dir,
      added_examples_dir: @added_examples_dir,
    ).execute!
  end

  def meta
    @meta ||= JSON.parse(File.read(@base_dir.join('meta.json')))
  end

  def write_event_api_summary
    event_api_pages = prepared_data.map do |type, data|
      info = meta['subscriptions'][type] || {}
      [info['url'], type, data, info['compatibility'], info['scopes']]
    end

    preset = @preset_definitions.merge(
      'subscription_type' => {
        "type": 'string',
        "enum": meta['types'],
      },
      'scope' => {
        "type": 'string',
        "enum": meta['scopes'],
      }
    )

    all_defined = JSON.parse(preset.to_json)
    all_schema = {}

    all_details = event_api_pages.map do |url, type, response, compatibility, scopes|
      schema, defined, used = to_schema(response, url, preset)
      schema[:description] = "learn more: #{url}"

      pre = preset.protect_merge!(defined)

      all_defined.protect_merge!(defined)

      base = used.uniq.inject({}) do |a, pre_key|
        pre[pre_key] ? a.protect_merge!(pre_key => pre[pre_key]) : a
      end

      normalized_response = response.inject({}) do |a, (k, v)|
        next a.protect_merge!(k => v) unless v.is_a?(Hash) && v['_type'] == 'enum'

        a.merge!(v['target'] => v['items'].map { |s| s || 'null' }.join('|'))
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
        "$schema": 'http://json-schema.org/draft-07/schema',
        'definitions' => defined.protect_merge!(type => schema),
      }

      data[:schema] = schema_data

      File.write(@schemas_dir.join("#{type}.json").to_s, JSON.pretty_generate(schema_data))
      File.write(@details_dir.join("#{type}.json").to_s, JSON.pretty_generate(data))
    end

    File.write(@base_dir.join('schema.json').to_s, JSON.pretty_generate({
      "$schema": 'http://json-schema.org/draft-07/schema',
      'definitions' => all_defined.protect_merge!(all_schema).key_ordered,
    }))
    File.write(@base_dir.join('summary.json').to_s, JSON.pretty_generate(all_details.sort_by { |a| a[:type] }))
  end
end

class ExamplePreparation
  using StrongHash

  def initialize(examples_dir:, added_examples_dir:)
    @added_examples_dir = added_examples_dir
    @examples_dir = examples_dir
  end

  def execute!
    posit_added_examples!

    single_events = Set.new(raw_examples.map(&:first))

    defined = Set.new
    event_typed_examples = {}
    alt_typed_examples = {}

    raw_examples.each do |alt_event_type, event_type, example|
      event_typed_examples.protect_merge!(event_type => JSON.parse(example.to_json))

      next alt_typed_examples.merge!(alt_event_type => example) if defined.add?(event_type)

      single_events.delete(event_type)
      defined_example = event_typed_examples[event_type]

      Set.new(defined_example.keys + example.keys).each do |k|
        additional_value = example[k]
        defined_value = defined_example[k]

        if k.match?('.*_type')
          if defined_value.is_a?(Hash) && defined_value['_type'] == 'enum'
            defined_value['items'] << additional_value
          else
            defined_example[k] = {
              '_type' => 'enum',
              'target' => k,
              'items' => [defined_value],
            }
          end
        end
      end
    end

    alt_typed_examples.select { |k, _| single_events.include?(k) }.protect_merge!(event_typed_examples)
  end

  private

  def posit_added_examples!
    Dir.glob(@added_examples_dir.join('**/*.json')).each do |f|
      file_name = File.basename(f)
      FileUtils.copy(f, @examples_dir.join(file_name))
    end
  end

  def raw_examples
    @raw_examples ||= Dir.glob(@examples_dir.join('**/*.json')).map do |f|
      example = JSON.parse(File.read(f))
      alt_event_type = File.basename(f, '.json')
      event_body = example['event'].presence || example
      event_type = event_body['type']

      [alt_event_type, event_type, event_body.key_ordered]
    end
  end
end