module SlackResources
  module Generator
    class ToSchema
      using StrongHash

      def initialize(response:, url:, preset:, key: 'root', defined: {}, defined_used: [], parent: {})
        @response = response
        @url = url
        @preset = preset
        @key = key
        @defined = defined
        @defined_used = defined_used
        @parent = parent
      end

      def execute!
        types = JSON.parse(@response.to_json).key_ordered

        def_string = ->(id_key) { id_key.tap { @defined.merge!(id_key => { 'type' => 'string' }) } }

        properties = types.inject({}) do |a, (k, v)|
          if v.is_a?(Hash)
            if v['_type'] && v['_type'] == 'enum'
              def_k = "#{@key == 'root' ? types['type'] : @key}_#{k}"
              @defined[def_k] = { 'type' => 'string', enum: v['items'] }
              next a.merge(k => { '$ref' => "#/definitions/#{def_k}" })
            end

            def_k =
              case
              when k == 'item'
                t = types['type'].split('_').shift
                "#{t}_item"
              else
                k
              end

            schema, = clone_with(
              response: v,
              key: k,
              parent: types,
            ).execute!

            @defined_used << def_k
            @defined[def_k] = schema
            next a.merge(k => { '$ref' => "#/definitions/#{def_k}" })
          end

          type =
            case k
            when @key == 'root' && 'type'
              { 'const' => v }
            when @key == 'root' && 'subtype'
              def_string.call('subscription_subtype')
            when @key == 'event' && 'type'
              { 'const' => v }
            when @key == 'item' && 'type'
              t = @parent['type'].split('_').shift
              def_string.call("#{t}_#{@key}_type")
            when 'type'
              def_string.call("#{@key}_type")

            when 'name'
              def_string.call("#{@key}_name")
            when 'id'
              def_string.call("#{@key}_id")
            when /.+_id$/
              def_string.call(k)

            when types['type'] == 'emoji_changed' && 'names'
              def_string.call('emoji_name')
              '[]emoji_name'
            when 'reaction'
              def_string.call('emoji_name')
              'emoji_name'
            when types['type'] == 'team_rename' && 'name'
              'team_name'

            when string_k_v('item_user', v),
              string_k_v('user', v),
              string_k_v('creator', v),
              string_k_v('inviter', v),
              string_k_v('created_by', v),
              string_k_v('updated_by', v),
              string_k_v('deleted_by', v)
              def_string.call('user_id')
            when string_k_v('channel', v)
              def_string.call('channel_id')
            when string_k_v('comment', v)
              def_string.call('comment_id')
            when string_k_v('team', v)
              def_string.call('team_id')

            when 'authed_users', 'authed_users', 'users', 'added_users', 'removed_users'
              def_string.call('user_id')
              '[]user_id'
            when 'authed_teams'
              def_string.call('team_id')
              '[]team_id'
            when 'channels'
              def_string.call('channel_id')
              '[]channel_id'
            when 'groups'
              def_string.call('group_id')
              '[]group_id'

            when 'scopes'
              '[]scope'
            when 'links'
              '[]link'

            when 'user_count', 'added_users_count', 'removed_users_count'
              'user_count'

            when 'resources'
              @defined['resource_item'] = clone_with(
                response: v.first,
                key: k,
                parent: types,
              ).execute!

              '[]resource_item'

            when v.is_a?(Integer) && k
              'time_integer'
            when (v == true || v == false) && k
              'boolean'
            when 'email_domain', 'text', 'description', 'handle', 'url', 'domain'
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
                def_string.call(k)
                'string'
              else
                v
              end
            end

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
                  response: v.first,
                  key: item,
                  parent: types,
                ).execute!

                @defined[item] = schema
              elsif v.first.is_a?(String)
                def_string.call(item)
              end

              @defined_used << item
            end
            a.merge(
              k => {
                'type' => 'array',
                'items' => {
                  '$ref' => "#/definitions/#{item}",
                },
              }
            )
          else
            @defined_used << type
            a.merge(
              k => {
                '$ref' => "#/definitions/#{type}",
              }
            )
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

      def clone_with(params = {})
        SlackResources::Generator::ToSchema.new(
          response: @response,
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
        type == 'string' || type == 'number' || type == 'object' || type == 'array' || type == 'boolean' || type == 'null'
      end
    end
  end
end
