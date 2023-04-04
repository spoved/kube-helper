require "../src/kube/types"
require "open-api"

class Schema
  def schema
    Open::Api::Schema.from_type(Config)
    # Open::Api::Schema.from_type(AppOptions)
  end
end

schema = Schema.new.schema

jschema = {
  "$schema"     => "http://json-schema.org/draft-06/schema#",
  "$ref"        => "#/definitions/Config",
  "definitions" => {
    "Config" => schema,
  },
}

puts jschema.to_pretty_json

# puts Open::Api::Schema.from_type("Hash(String, YAML::Any) | String | Nil").to_pretty_json
# puts Open::Api::Schema.from_type("AppOptions").to_pretty_json
