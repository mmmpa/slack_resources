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

    all_sub_schemas = prepare_definitions
    main_schemas = {}

    all_details = combine_data(meta, prepared_data).map do |url, alt_event_type, example, compatibility, scopes|
      schema, new_definition, included_props_names = SlackResources::Generator::ToSchema.new(
        example: example,
        url: url,
        preset: all_sub_schemas
      ).execute!

      schema[:description] = "learn more: #{url}"

      all_sub_schemas.protect_merge!(new_definition)

      included_schemas = included_props_names.inject({}) do |a, included_prop|
        a.protect_merge!(included_prop => all_sub_schemas[included_prop])
      end

      normalized_response = example.inject({}) do |a, (k, v)|
        next a.protect_merge!(k => v) unless v.is_a?(Hash) && v['_type'] == 'enum'

        a.merge!(v['target'] => v['items'].map { |s| s || 'null' }.join('|'))
      end

      schema.protect_merge!(example: normalized_response)

      main_schemas.merge!(alt_event_type => schema)

      [
        alt_event_type,
        {
          url: url,
          event: alt_event_type,
          sub_schemas: included_schemas,
          schema: schema,
          compatibility: compatibility,
          scopes: scopes,
        },
        {
          "$schema": 'http://json-schema.org/draft-07/schema',
          'definitions' => included_schemas.protect_merge!(alt_event_type => schema),
        },
      ]
    end

    write_each_data_json!(all_details)
    write_all_schemas_json!(all_sub_schemas, main_schemas)
    write_summary!(all_details.map { |d| d[2] })
  end

  # @base_dir = Pathname('./lib/slack_resources/resources/event_api/')

  private

  def write_each_data_json!(all_details)
    all_details.each do |alt_event_type, data, single_schema|
      File.write(@details_dir.join("#{alt_event_type}.json").to_s, JSON.pretty_generate(data))
      File.write(@schemas_dir.join("#{alt_event_type}.json").to_s, JSON.pretty_generate(single_schema))
    end
  end

  def write_all_schemas_json!(all_sub_schemas, main_schemas)
    File.write(
      @base_dir.join('schema.json').to_s,
      JSON.pretty_generate(
        "$schema": 'http://json-schema.org/draft-07/schema',
        'definitions' => all_sub_schemas.protect_merge!(main_schemas).key_ordered,
      )
    )
  end

  def write_summary!(data)
    File.write(@base_dir.join('summary.json').to_s, JSON.pretty_generate(data.sort_by { |a| a[:type] }))
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

  def prepare_definitions
    @preset_definitions.merge(
      'subscription_type' => {
        "type": 'string',
        "enum": meta['types'],
      },
      'scope' => {
        "type": 'string',
        "enum": meta['scopes'],
      }
    )
  end
end
