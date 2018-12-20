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

        properties = types.inject({}) do |a, (prop_name, v)|
          type = TypeDetection.new(
            parent_key: @key,
            to_schema: self,
            prop_name: prop_name,
            value: v,
            container: types,
            preset: @preset
          ).execute!

          @defined_used << type

          case
          when TypeDetection.default_type?(type)
            a.merge(prop_name => { 'type' => type })
          when detail?(type)
            a.merge(prop_name => type)
          when array_type?(type)
            a.merge(prop_name => define_as_array(type, v, types))
          else
            a.merge(prop_name => ref_to(type))
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
        @root == @example
      end

      def root_type
        @root['type']
      end

      def root_type_prefix
        @root_type_prefix ||= root_type.split('_').shift
      end

      def array_type?(type)
        type.to_s[0..1] == '[]'
      end

      def detail?(type)
        type.is_a?(Hash)
      end

      def define_as_array(array_type, values, types)
        type = array_type[2..-1]

        if TypeDetection.default_type?(type)
          return {
            'type' => 'array',
            'items' => {
              'type' => type,
            },
          }
        end

        if values.first.is_a?(Hash)
          to_child_schema(
            prop_name: type,
            example: values.first,
            key: type,
            parent: types
          )
        elsif values.first.is_a?(String)
          define_string(type)
        end

        {
          'type' => 'array',
          'items' => ref_to(type),
        }
      end

      def define_object(k, v, types)
        ref_key = k == 'item' ? "#{root_type_prefix}_item" : k

        to_child_schema(
          prop_name: ref_key,
          example: v,
          key: k,
          parent: types
        )

        ref_key
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
        ).execute!.tap do |schema,|
          @defined[prop_name] = schema
        end
      end
    end
  end
end
