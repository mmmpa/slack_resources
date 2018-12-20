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

      USER_ID_ARRAY_PROPERTIES = Set.new(['authed_users', 'authed_users', 'users', 'added_users', 'removed_users'])
      STRING_USER_ID_PROPERTIES = Set.new(%w[
item_user
user
creator
inviter
created_by
updated_by
deleted_by
      ])
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

      def initialize(example:, url:, preset:, key: 'root', defined: {}, defined_used: [], parent: {})
        @example = JSON.parse(example.to_json).key_ordered
        @url = url
        @preset = preset
        @key = key
        @defined = defined
        @defined_used = defined_used
        @parent = parent
      end

      def execute!
        types = JSON.parse(@example.to_json).key_ordered

        def_string = ->(id_key) { id_key.tap { @defined.merge!(id_key => { 'type' => 'string' }) } }

        properties = types.inject({}) do |a, (k, v)|
          next a.merge!(k => ref_to(define_object(k, v, types))) if object?(v)
          next a.merge!(k => ref_to(define_enum(k, v, types))) if enum?(v)

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
                  parent: types,
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

      def item_schema?
        @key == 'item'
      end

      def define_object(k, v, types)
        ref_key =
          case
          when k == 'item'
            t = types['type'].split('_').shift
            "#{t}_item"
          else
            k
          end

        schema, = clone_with(
          example: v,
          key: k,
          parent: types,
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

      def define_enum(k, v, types)
        ref_key = "#{root_schema? ? types['type'] : @key}_#{k}"
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
          t = @parent['type'].split('_').shift
          define_string("#{t}_#{@key}_type")
        when 'type'
          define_string("#{@key}_type")

        when 'name'
          define_string("#{@key}_name")
        when 'id'
          define_string("#{@key}_id")
        when /.+_id$/
          define_string(k)

        when types['type'] == 'emoji_changed' && 'names'
          define_string('emoji_name')
          '[]emoji_name'
        when 'reaction'
          define_string('emoji_name')
          'emoji_name'
        when types['type'] == 'team_rename' && 'name'
          'team_name'

        when user_id?(k, v)
          define_string('user_id')
        when string_k_v('channel', v)
          define_string('channel_id')
        when string_k_v('comment', v)
          define_string('comment_id')
        when string_k_v('team', v)
          define_string('team_id')

        when user_id_array?(k)
          define_string('user_id')
          '[]user_id'
        when 'authed_teams'
          define_string('team_id')
          '[]team_id'
        when 'channels'
          define_string('channel_id')
          '[]channel_id'
        when 'groups'
          define_string('group_id')
          '[]group_id'

        when 'scopes'
          '[]scope'
        when 'links'
          '[]link'

        when user_count?(k)
          'user_count'

        when 'resources'
          @defined['resource_item'] = clone_with(
            example: v.first,
            key: k,
            parent: types,
          ).execute!

          '[]resource_item'

        when v.is_a?(Integer) && k
          'time_integer'
        when (v == true || v == false) && k
          'boolean'
        when direct_string?(k)
          'string'
        when @parent['type'] == 'tokens_revoked' && 'oauth'
          '[]string'
        when @parent['type'] == 'tokens_revoked' && 'bot'
          '[]string'
        when 'latest', /.+_ts$/
          'timestamp'
        when @preset[k] && k
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

      def user_id_array?(k)
        k if USER_ID_ARRAY_PROPERTIES.include?(k)
      end

      def user_count?(k)
        k if USER_COUNT_PROPERTIES.include?(k)
      end

      def direct_string?(k)
        k if DIRECT_STRING_PROPERTIES.include?(k)
      end

      def user_id?(k, v)
        string_k_v(k, v) if STRING_USER_ID_PROPERTIES.include?(k)
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
          **params,
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
