require 'active_support/core_ext/hash/keys'

module SlackResources
  module Generator
    class ToSchema
      using StrongHash

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

          type = TypeDetection.new(
            parent_key: @key,
            to_schema: self,
            prop_name: k,
            value: v,
            container: types,
            preset: @preset
          ).execute!

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
                to_child_schema(
                  prop_name: item,
                  example: v.first,
                  key: item,
                  parent: types
                )
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

      def define_object(k, v, types)
        ref_key = k == 'item' ? "#{root_type_prefix}_item" : k

        to_child_schema(
          prop_name: ref_key,
          example: v,
          key: k,
          parent: types
        )

        @defined_used << ref_key

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

      def to_child_schema(params)
        prop_name = params.delete(:prop_name)
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
        ).execute!.tap { |schema,| @defined[prop_name] = schema }
      end

      def default_type?(type)
        TypeDetection::DEFAULT_TYPES.include?(type)
      end
    end
  end
end
