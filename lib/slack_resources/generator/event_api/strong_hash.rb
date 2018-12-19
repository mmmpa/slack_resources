module SlackResources
  module Generator
    module StrongHash
      refine Hash do
        def protect_merge!(b)
          (b.keys - keys).map do |new_key|
            self[new_key] = b[new_key]
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
