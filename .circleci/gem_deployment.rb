class GemDeployment
  CREDENTIAL_DIR_PATH = '~/.gem/credentials'
  CREDENTIAL_FILE_PATH = '~/.gem/credentials'
  VERSION_FILE_PATH = './lib/slack_resources/version.rb'

  def initialize(api_key = '', version = 'tiny')
    @api_key = api_key
    @version = version
  end

  def execute!
    major, minor, tiny = fetch_version

    major += 1 if major?
    minor += 1 if minor?
    tiny += 1 if tiny?

    next_version = [major, minor, tiny].join('.')

    `echo "---\n:rubygems_api_key: #{@api_key}\n" > ~/.gem/credentials && chmod 600 ~/.gem/credentials`

    File.write(VERSION_FILE_PATH, <<~VER)
      module SlackResources
        VERSION = '#{next_version}'.freeze
      end
    VER

    result = `gem build slack_resources.gemspec`
    puts result
    gem_file = result.match(/File: *(.+)\n/m)[1]
    puts `gem push #{gem_file}`
  end

  private

  def fetch_version
    `gem search slack_resources`.match(/\(([\d.]+)\)/)[1].split('.').map(&:to_i)
  end

  def major?
    @version == 'major'
  end

  def minor?
    @version == 'minor'
  end

  def tiny?
    @version == 'tiny'
  end
end

GemDeployment.new(*ARGV).execute! if __FILE__ == $0
