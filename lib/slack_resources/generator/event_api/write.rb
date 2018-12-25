require 'pathname'
require 'nokogiri'
require 'json'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/string/inflections'

module SlackResources
  module Generator
    class Writer
      using StrongHash

      def initialize(output_dir:, data_dir:)
        @output_dir = Pathname(output_dir)
        @details_output_dir = @output_dir.join('details')
        @schemas_output_dir = @output_dir.join('schemas')
        @example_output_dir = @output_dir.join('examples')

        @data_dir = Pathname(data_dir)
        @meta = JSON.parse(File.read(@data_dir.join('meta.json')))
        @preset_schema = JSON.parse(File.read(@data_dir.join('preset_schemas.json')))
        @preset_definitions = @preset_schema['definitions']

        @examples_dir = @data_dir.join('examples')
        @added_examples_dir = @data_dir.join('_added_examples')
      end

      def execute!
        FileUtils.mkdir_p(@details_output_dir)
        FileUtils.mkdir_p(@schemas_output_dir)
        FileUtils.mkdir_p(@example_output_dir)

        alt_event_type_mapped_examples = ExamplePreparation.new(
          examples_dir: @examples_dir,
          added_examples_dir: @added_examples_dir
        ).execute!

        examples_with_metadata = alt_event_type_mapped_examples.map do |alt_event_type, example|
          info = @meta['subscriptions'][alt_event_type] || @meta['subscriptions'][example['type']] || {}
          [info['url'], alt_event_type, example, info['compatibility'], info['scopes']]
        end

        all_sub_schemas = @preset_definitions.merge(
          'scope' => {
            "type": 'string',
            "enum": @meta['scopes'],
          }
        )

        main_schemas = {}

        all_details = examples_with_metadata.map do |url, alt_event_type, example, compatibility, scopes|
          raw_example = example.delete('_raw_example')
          schema, new_definition, included_props_names = ToSchema.new(
            example: example,
            url: url,
            preset: all_sub_schemas
          ).execute!

          all_sub_schemas.protect_merge!(new_definition)

          included_schemas = included_props_names.inject({}) do |a, included_prop|
            all_sub_schemas[included_prop] ? a.protect_merge!(included_prop => all_sub_schemas[included_prop]) : a
          end

          schema['description'] = "learn more: #{url}"
          schema['example'] = raw_example

          main_schemas[alt_event_type] = schema

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
            raw_example,
          ]
        end

        write_each_data_json!(all_details)
        write_all_schemas_json!(all_sub_schemas, main_schemas)
        write_summary!(all_details.map { |d| d[1] })

        all_details
      end

      # @output_dir = Pathname('./lib/slack_resources/resources/event_api/')

      private

      def write_each_data_json!(all_details)
        all_details.each do |alt_event_type, data, single_schema, example|
          File.write(@details_output_dir.join("#{alt_event_type}.json").to_s, JSON.pretty_generate(data))
          File.write(@example_output_dir.join("#{alt_event_type}.json").to_s, JSON.pretty_generate(example))
          File.write(@schemas_output_dir.join("#{alt_event_type}.json").to_s, JSON.pretty_generate(single_schema))
        end
      end

      def write_all_schemas_json!(all_sub_schemas, main_schemas)
        File.write(
          @output_dir.join('schema.json').to_s,
          JSON.pretty_generate(
            "$schema": 'http://json-schema.org/draft-07/schema',
            'definitions' => all_sub_schemas.protect_merge!(main_schemas).key_ordered
          )
        )
      end

      def write_summary!(data)
        File.write(@output_dir.join('summary.json').to_s, JSON.pretty_generate(data.sort_by { |a| a[:type] }))
      end
    end
  end
end
