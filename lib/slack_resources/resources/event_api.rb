require 'pathname'

module SlackResources
  module Resources
    module EventApi
      BASE_PATH = Pathname(__dir__).join('event_api')

      SUMMARY_PATH = BASE_PATH.join('summary.json')
      DETAILS_PATH = BASE_PATH.join('details')
      EXAMPLES_PATH = BASE_PATH.join('examples')
      SCHEMAS_PATH = BASE_PATH.join('schemas')

      class << self
        def details(name)
          File.read(DETAILS_PATH.join("#{name}.json"))
        end

        def example(name)
          File.read(EXAMPLES_PATH.join("#{name}.json"))
        end

        def schemas(name)
          File.read(SCHEMAS_PATH.join("#{name}.json"))
        end

        def event_types
          summary_file.map { |h| h['event'] }
        end

        private

        def summary_file
          @summary_file = JSON.parse(File.read(SUMMARY_PATH))
        end
      end
    end
  end
end
