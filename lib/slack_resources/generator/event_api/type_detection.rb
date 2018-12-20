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

      def execute!
        case
        when root_schema? && @prop_name == 'type'
          { 'const' => @value }
        when root_schema? && @prop_name == 'subtype'
          define_string('subscription_subtype')
        when item_schema? && @prop_name == 'type'
          define_string("#{root_type_prefix}_#{@parent_key}_type")

        when ambient?
          define_string("#{@parent_key}_#{@prop_name}")

        when @container['type'] == 'emoji_changed' && @prop_name == 'names'
          define_string('emoji_name')
          '[]emoji_name'
        when @prop_name == 'reaction'
          define_string('emoji_name')
          'emoji_name'

        when string_id?
          detect_string_id

        when array?
          detect_array_type

        when user_count?
          'user_count'

        when @value.is_a?(Integer)
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
          if @value.respond_to?(:to_f) && @value == @value.to_f.to_s
            'timestamp'
          elsif @value.is_a?(String)
            define_string(@prop_name)
            'string'
          else
            @value
          end
        end
      end

      private

      def ambient?
        AMBIENT_PROPERTIES.include?(@prop_name)
      end

      def boolean?
        BOOLEAN.include?(@value)
      end

      def timestamp?
        @prop_name == 'latest' || @prop_name.match(/.+_ts$/)
      end

      def array?
        ARRAY_PROPERTIES.include?(@prop_name) || (on_tokens_revoked? && TOKENS_REVOKED_ARRAY_PROPERTIES.include?(@prop_name))
      end

      def user_count?
        USER_COUNT_PROPERTIES.include?(@prop_name)
      end

      def direct_string?
        DIRECT_STRING_PROPERTIES.include?(@prop_name)
      end

      def preset_included?
        !!@preset[@prop_name]
      end

      def detect_array_type
        type = ARRAY_PROPERTIES_TYPE_MAP[@prop_name]
        array_type = "[]#{type}"
        return array_type if default_type?(type)

        if @value.is_a?(Hash)
          @defined[type] = clone_with(
            example: @value.first,
            key: @prop_name,
            parent: @container
          ).execute!
        else
          define_string(type)
        end

        array_type
      end

      def string_id?
        @prop_name.match(/_id$/) || (string_value? && STRING_ID_PROPERTIES.include?(@prop_name))
      end

      def detect_string_id
        type = STRING_ID_PROPERTIES_MAP[@prop_name] || @prop_name
        define_string(type)

        type
      end

      def string_value?
        @value.nil? || @value.is_a?(String)
      end

      def default_type?(type)
        DEFAULT_TYPES.include?(type)
      end

      def on_tokens_revoked?
        root_type == 'tokens_revoked'
      end
    end
  end
end
