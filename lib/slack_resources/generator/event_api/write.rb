require 'pathname'
require 'rest-client'
require 'nokogiri'
require 'json'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/string/inflections'

require 'slack_resources/generator/event_api/strong_hash'
require 'slack_resources/generator/event_api/examples_preparation'
require 'slack_resources/generator/event_api/to_schema'

class Writer
  using SlackResources::Generator::StrongHash

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

  def to_schema(example, url, preset_schema = JSON.parse(@preset_schema.to_json))
    schema, defined, defined_used = SlackResources::Generator::ToSchema.new(
      example: example,
      url: url,
      preset: preset_schema
    ).execute!

    [schema, defined, defined_used]
  end

  def safe_merge(a, b)
    (b.keys - a.keys).map do |new_key|
      a[new_key] = b[new_key]
    end

    a
  end

  def prepared_data
    SlackResources::Generator::ExamplePreparation.new(
      examples_dir: @examples_dir,
      added_examples_dir: @added_examples_dir
    ).execute!
  end

  def meta
    @meta ||= JSON.parse(File.read(@base_dir.join('meta.json')))
  end

  def combine_data(meta, examples)
    examples.map do |alt_event_type, example|
      info = meta['subscriptions'][alt_event_type] || {}
      [info['url'], alt_event_type, example, info['compatibility'], info['scopes']]
    end
  end

  def write_event_api_summary
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

    all_details = combine_data(meta, prepared_data).map do |url, alt_event_type, example, compatibility, scopes|
      schema, defined, used = to_schema(example, url, preset)
      schema[:description] = "learn more: #{url}"

      pre = preset.protect_merge!(defined)

      all_defined.protect_merge!(defined)

      base = used.uniq.inject({}) do |a, pre_key|
        pre[pre_key] ? a.protect_merge!(pre_key => pre[pre_key]) : a
      end

      normalized_response = example.inject({}) do |a, (k, v)|
        next a.protect_merge!(k => v) unless v.is_a?(Hash) && v['_type'] == 'enum'

        a.merge!(v['target'] => v['items'].map { |s| s || 'null' }.join('|'))
      end

      {
        url: url,
        type: alt_event_type,
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
