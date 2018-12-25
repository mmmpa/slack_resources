require 'pathname'
require 'json'

module SlackResources
  module Resources
    module EventApi
      BASE_PATH = Pathname(__dir__).join('event_api')

      SUMMARY_PATH = BASE_PATH.join('summary.json')
      DETAILS_PATH = BASE_PATH.join('details')
      EXAMPLES_PATH = BASE_PATH.join('examples')
      SCHEMAS_PATH = BASE_PATH.join('schemas')

      class << self
        def detail(name)
          JSON.parse(File.read(DETAILS_PATH.join("#{name}.json")))
        end

        def example(name)
          JSON.parse(File.read(EXAMPLES_PATH.join("#{name}.json")))
        end

        def schema(name)
          JSON.parse(File.read(SCHEMAS_PATH.join("#{name}.json")))
        end

        def schemas
          JSON.parse(File.read(BASE_PATH.join('schemas.json')))
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
