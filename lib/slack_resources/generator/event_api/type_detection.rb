require 'active_support/core_ext/module/delegation'

module SlackResources
  module Generator
    class TypeDetection
      using StrongHash

      DEFAULT_TYPES = Set.new(%w[
        string
        number
        object
        array
        boolean
        null
      ])

      STRING_ID_PROPERTIES_MAP = {
        item_user: 'user_id',
        user: 'user_id',
        creator: 'user_id',
        inviter: 'user_id',
        created_by: 'user_id',
        updated_by: 'user_id',
        deleted_by: 'user_id',
        channel: 'channel_id',
        comment: 'comment_id',
        team: 'team_id',
      }.stringify_keys!

      STRING_ID_PROPERTIES = Set.new(STRING_ID_PROPERTIES_MAP.keys)

      DIRECT_STRING_PROPERTIES = Set.new(%w[
        email_domain
        text
        description
        handle
        url
        domain
      ])

      USER_COUNT_PROPERTIES = Set.new(%w[
        user_count
        added_users_count
        removed_users_count
      ])

      ARRAY_PROPERTIES_TYPE_MAP = {
        authed_users: 'user_id',
        users: 'user_id',
        added_users: 'user_id',
        removed_users: 'user_id',
        authed_teams: 'team_id',
        channels: 'channel_id',
        groups: 'group_id',
        scopes: 'scope',
        links: 'link',
        oauth: 'string',
        bot: 'string',
        resources: 'resource_item',
      }.stringify_keys!

      TOKENS_REVOKED_ARRAY_PROPERTIES = Set.new(%w[
        oauth
        bot
      ])

      ARRAY_PROPERTIES = Set.new(ARRAY_PROPERTIES_TYPE_MAP.keys - TOKENS_REVOKED_ARRAY_PROPERTIES.to_a)

      BOOLEAN = Set.new([true, false])

      AMBIENT_PROPERTIES = Set.new(%w[
        id
        type
        name
      ])

      delegate :root_schema?, :item_schema?, :define_string, :root_type, :root_type_prefix, to: :@to_schema

      def initialize(to_schema:, parent_key:, prop_name:, value:, container:, preset:)
        @parent_key = parent_key
        @to_schema = to_schema
        @prop_name = prop_name
        @value = value
        @container = container
        @preset = preset
      end

      def execute! # rubocop:disable Metrics/PerceivedComplexity,Metrics/CyclomaticComplexity
        case
        when root_schema? && type?
          { 'const' => @value }
        when root_schema? && sub_type?
          define_string('subscription_subtype')
        when item_schema? && type?
          define_string("#{root_type_prefix}_#{@parent_key}_type")

        when string_id?
          define_string_id
        when ambient?
          define_string("#{@parent_key}_#{@prop_name}")

        when emoji_list?
          define_string('emoji_name')
          '[]emoji_name'
        when emoji_alternative?
          define_string('emoji_name')

        when array?
          define_array_type

        when user_count?
          'user_count'
        when time_integer?
          'time_integer'
        when boolean?
          'boolean'
        when direct_string?
          'string'
        when timestamp?
          'timestamp'

        when preset_included?
          @prop_name

        else
          define_string(@prop_name)
          'string'
        end
      end

      private

      def type?
        @prop_name == 'type'
      end

      def sub_type?
        @prop_name == 'subtype'
      end

      def emoji_alternative?
        @prop_name == 'reaction'
      end

      def ambient?
        AMBIENT_PROPERTIES.include?(@prop_name)
      end

      def time_integer?
        @value.is_a?(Integer)
      end

      def boolean?
        BOOLEAN.include?(@value)
      end

      def timestamp?
        @prop_name == 'latest' || @prop_name.match(/.+_ts$/) || float_string?
      end

      def float_string?
        @value.respond_to?(:to_f) && @value == @value.to_f.to_s
      end

      def array?
        ARRAY_PROPERTIES.include?(@prop_name) || tokens_revoked_array?
      end

      def tokens_revoked_array?
        on_tokens_revoked? && TOKENS_REVOKED_ARRAY_PROPERTIES.include?(@prop_name)
      end

      def user_count?
        USER_COUNT_PROPERTIES.include?(@prop_name)
      end

      def direct_string?
        DIRECT_STRING_PROPERTIES.include?(@prop_name)
      end

      def preset_included?
        @preset.key?(@prop_name)
      end

      def string_id?
        @prop_name.match(/_id$/) || (string_value? && STRING_ID_PROPERTIES.include?(@prop_name))
      end

      def string_value?
        @value.nil? || @value.is_a?(String)
      end

      def default_type?(type)
        DEFAULT_TYPES.include?(type)
      end

      def emoji_list?
        on_emoji_changed? && @prop_name == 'names'
      end

      def on_tokens_revoked?
        root_type == 'tokens_revoked'
      end

      def on_emoji_changed?
        root_type == 'emoji_changed'
      end

      def define_array_type
        type = ARRAY_PROPERTIES_TYPE_MAP[@prop_name]
        array_type = "[]#{type}"

        return array_type if default_type?(type)
        return define_string(type) && array_type unless @value.is_a?(Hash)

        to_child_schema(
          prop_name: type,
          example: @value.first,
          key: @prop_name,
          parent: @container
        )

        array_type
      end

      def define_string_id
        type = STRING_ID_PROPERTIES_MAP[@prop_name] || @prop_name
        define_string(type)
      end
    end
  end
end
