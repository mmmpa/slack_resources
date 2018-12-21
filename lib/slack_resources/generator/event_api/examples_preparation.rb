module SlackResources
  module Generator
    class ExamplePreparation
      using StrongHash

      def initialize(examples_dir:, added_examples_dir:)
        @added_examples_dir = added_examples_dir
        @examples_dir = examples_dir
      end

      def execute!
        single_events = Set.new(raw_examples.map(&:first))

        defined = Set.new
        event_typed_examples = {}
        alt_typed_examples = {}

        raw_examples.each do |alt_event_type, event_type, example|
          example['_raw_example'] = JSON.parse(example.to_json)
          event_typed_examples.protect_merge!(event_type => example)
          alt_typed_examples[alt_event_type] = JSON.parse(example.to_json)

          next if defined.add?(event_type)

          single_events.delete(event_type)
          defined_example = event_typed_examples[event_type]

          Set.new(defined_example.keys + example.keys).each do |k|
            next if k == '_raw_example'

            defined_value = defined_example[k]
            additional_value = example[k]

            next if defined_value == additional_value

            if defined_value.is_a?(Hash) && defined_value[TypeDetection::SPECIAL_TYPE] == TypeDetection::MULTIPLE_EXAMPLES
              (defined_value['items'] << additional_value).sort! { |a, b| a.to_s <=> b.to_s }
            else
              defined_example.merge!(
                k => {
                  TypeDetection::SPECIAL_TYPE => TypeDetection::MULTIPLE_EXAMPLES,
                  'target' => k,
                  'items' => [defined_value, additional_value].sort! { |a, b| a.to_s <=> b.to_s },
                }
              )
            end
          end
        end

        alt_typed_examples.select { |k, _| single_events.include?(k) }.protect_merge!(event_typed_examples)
      end

      private

      def all_files
        Dir.glob(@added_examples_dir.join('**/*.json')) + Dir.glob(@examples_dir.join('**/*.json'))
      end

      def raw_examples
        @raw_examples ||= all_files.map do |f|
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
