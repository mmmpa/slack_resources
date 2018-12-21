module SlackResources
  module Generator
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
          event_typed_examples.protect_merge!(event_type => example)

          next alt_typed_examples.merge!(alt_event_type => JSON.parse(example.to_json)) if defined.add?(event_type)

          alt_typed_examples[alt_event_type] = JSON.parse(example.to_json)

          single_events.delete(event_type)
          defined_example = event_typed_examples[event_type]

          Set.new(defined_example.keys + example.keys).each do |k|
            next unless k.match?('.*_type')

            defined_value = defined_example[k]
            additional_value = example[k]

            if defined_value.is_a?(Hash) && defined_value['_type'] == 'enum'
              defined_value['items'] << additional_value
            else
              defined_example.merge!(
                k => {
                  '_type' => 'enum',
                  'target' => k,
                  'items' => [defined_value],
                }
              )
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
  end
end
