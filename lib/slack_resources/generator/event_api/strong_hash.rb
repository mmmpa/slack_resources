module SlackResources
  module Generator
    module StrongHash
      refine Hash do
        def protect_merge!(b)
          b.keys.map do |new_key|
            if self[new_key]
              self[new_key] = b[new_key] if b[new_key].is_a?(Hash) && b[new_key]['type'].is_a?(Array)
            else
              self[new_key] = b[new_key]
            end
          end

          self
        end

        def key_ordered
          keys.sort.inject({}) do |a, k|
            a.merge!(k => self[k])
          end
        end
      end
    end
  end
end
