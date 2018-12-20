require 'active_support/core_ext/hash/keys'

module SlackResources
  module Generator
    class ToSchema
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

      def initialize(example:, url:, preset:, key: 'root', defined: {}, defined_used: [], parent: {}, root: nil)
        @example = JSON.parse(example.to_json).key_ordered
        @url = url
        @preset = preset
        @key = key
        @defined = defined
        @defined_used = defined_used
        @parent = parent
        @root = root || example
      end

      def execute!
        types = JSON.parse(@example.to_json).key_ordered

        properties = types.inject({}) do |a, (k, v)|
          next a.merge!(k => ref_to(define_object(k, v, types))) if object?(v)
          next a.merge!(k => ref_to(define_enum(k, v))) if enum?(v)

          type = detect_type(k, v, types)

          if default_type?(type)
            a.merge(k => { 'type' => type })
          elsif type.is_a?(Hash)
            a.merge(k => type)
          elsif type && type[0..1] == '[]'
            item = type[2..-1]
            if default_type?(item)
              next a.merge(
                k => {
                  'type' => 'array',
                  'items' => {
                    'type' => item,
                  },
                }
              )
            else
              if v.first.is_a?(Hash)
                schema, = clone_with(
                  example: v.first,
                  key: item,
                  parent: types
                ).execute!

                @defined[item] = schema
              elsif v.first.is_a?(String)
                define_string(item)
              end

              @defined_used << item
            end
            a.merge(
              k => {
                'type' => 'array',
                'items' => ref_to(item),
              }
            )
          else
            @defined_used << type
            a.merge(k => ref_to(type))
          end
        end

        [
          {
            'type' => 'object',
            description: properties.blank? ? "definition snipped. learn more: #{@url}" : '(defined by script)',
            'properties' => properties,
          },
          @defined,
          @defined_used,
        ]
      end

      private

      def root_schema?
        @key == 'root'
      end

      def root_type
        @root['type']
      end

      def root_type_prefix
        @root_type_prefix ||= root_type.split('_').shift
      end

      def item_schema?
        @key == 'item'
      end

      def on_tokens_revoked?
        root_type == 'tokens_revoked'
      end

      def define_object(k, v, types)
        ref_key = k == 'item' ? "#{root_type_prefix}_item" : k

        schema, = clone_with(
          example: v,
          key: k,
          parent: types
        ).execute!

        @defined_used << ref_key
        @defined[ref_key] = schema

        ref_key
      end

      def object?(v)
        v.is_a?(Hash) && !enum?(v)
      end

      def enum?(v)
        v.is_a?(Hash) && v['_type'] == 'enum'
      end

      def define_enum(k, v)
        ref_key = "#{root_schema? ? root_type : @key}_#{k}"
        @defined[ref_key] = { 'type' => 'string', enum: v['items'] }
        ref_key
      end

      def define_string(key)
        key.tap { @defined.protect_merge!(key => { 'type' => 'string' }) }
      end

      def ref_to(type)
        { '$ref' => "#/definitions/#{type}" }
      end

      def detect_type(k, v, types)
        case k
        when root_schema? && 'type'
          { 'const' => v }
        when root_schema? && 'subtype'
          define_string('subscription_subtype')
        when item_schema? && 'type'
          define_string("#{root_type_prefix}_#{@key}_type")

        when ambient?(k)
          define_string("#{@key}_#{k}")

        when types['type'] == 'emoji_changed' && 'names'
          define_string('emoji_name')
          '[]emoji_name'
        when 'reaction'
          define_string('emoji_name')
          'emoji_name'

        when string_id?(k, v)
          detect_string_id(k)

        when array?(k, v)
          detect_array_type(k, v, types)

        when user_count?(k)
          'user_count'

        when v.is_a?(Integer) && k
          'time_integer'
        when boolean?(k, v)
          'boolean'
        when direct_string?(k)
          'string'
        when timestamp?(k)
          'timestamp'
        when preset_included?(k)
          k
        else
          if v.respond_to?(:to_f) && v == v.to_f.to_s
            'timestamp'
          elsif v.is_a?(String)
            define_string(k)
            'string'
          else
            v
          end
        end
      end

      def ambient?(k)
        k if AMBIENT_PROPERTIES.include?(k)
      end

      def boolean?(k, v)
        k if BOOLEAN.include?(v)
      end

      def timestamp?(k)
        k if k == 'latest' || k.match(/.+_ts$/)
      end

      def array?(k, _v)
        k if ARRAY_PROPERTIES.include?(k) || (on_tokens_revoked? && TOKENS_REVOKED_ARRAY_PROPERTIES.include?(k))
      end

      def user_count?(k)
        k if USER_COUNT_PROPERTIES.include?(k)
      end

      def direct_string?(k)
        k if DIRECT_STRING_PROPERTIES.include?(k)
      end

      def preset_included?(k)
        k if @preset[k]
      end

      def detect_array_type(k, v, types)
        type = ARRAY_PROPERTIES_TYPE_MAP[k]
        array_type = "[]#{type}"
        return array_type if default_type?(type)

        if v.is_a?(Hash)
          @defined[type] = clone_with(
            example: v.first,
            key: k,
            parent: types
          ).execute!
        else
          define_string(type)
        end

        array_type
      end

      def string_id?(k, v)
        return k if k.match(/_id$/)
        string_k_v(k, v) if STRING_ID_PROPERTIES.include?(k)
      end

      def detect_string_id(k)
        type = STRING_ID_PROPERTIES_MAP[k] || k
        define_string(type)

        type
      end

      def clone_with(params = {})
        SlackResources::Generator::ToSchema.new(
          example: @example,
          url: @url,
          preset: @preset,
          key: @key,
          defined: @defined,
          defined_used: @defined_used,
          parent: @parent,
          root: @root,
          **params
        )
      end

      def string_k_v(k, v)
        (v.nil? || v.is_a?(String)) && k
      end

      def default_type?(type)
        DEFAULT_TYPES.include?(type)
      end
    end
  end
end
