require "yaml"
require "json"

class Config
  include JSON::Serializable
  include YAML::Serializable

  property context : String? = nil
  property helm : Helm = Helm.new
  property secrets : Array(Secret) = Array(Secret).new
  property config_maps : Array(Secret) = Array(Secret).new
  property namespaces : Array(Namespace) = Array(Namespace).new
  property manifests : Array(String) = Array(String).new
  property apps : Array(AppOptions) = Array(AppOptions).new
  property groups : Array(Group) = Array(Group).new
  property kustomize : Array(KustomizeConfig) = Array(KustomizeConfig).new
  property annotations : Hash(String, String) = Hash(String, String).new

  def initialize; end
end

struct KustomizeConfig
  include JSON::Serializable
  include YAML::Serializable
  property name : String
  property namespace : String? = nil
  property path : String

  def initialize(@name, @namespace, @path); end
end

class Group
  include JSON::Serializable
  include YAML::Serializable

  property name : String
  property secrets : Array(Secret) = Array(Secret).new
  property config_maps : Array(Secret) = Array(Secret).new
  property apps : Array(AppOptions) = Array(AppOptions).new
  property before : Array(String) = Array(String).new
  property after : Array(String) = Array(String).new
  property ignore : Bool = false
  property project : String? = nil
  property default_namespace : String? = nil
  property istio : Bool = false

  property run_before : Array(String) = Array(String).new
  property run_after : Array(String) = Array(String).new

  def namespace : Namespace
    if self.default_namespace.nil?
      Namespace.new(self.name, self.project, self.istio)
    else
      Namespace.new(self.default_namespace.not_nil!, nil, self.istio)
    end
  end
end

class Namespace
  include JSON::Serializable
  include YAML::Serializable
  property name : String
  property project : String? = nil
  property istio : Bool = false

  def initialize(@name, @project, @istio = false); end
end

class Helm
  include JSON::Serializable
  include YAML::Serializable
  property repos : Repos = Repos.new

  def initialize; end
end

alias Values = Hash(String, YAML::Any)
alias Repos = Hash(String, String)

class AppOptions
  include JSON::Serializable
  include YAML::Serializable

  property name : String
  property kustomize : String? = nil
  property chart : String? = nil
  property chart_url : String? = nil
  property chart_path : String? = nil
  property version : String? = nil
  property namespace : String? = nil
  property values : String | Values | Nil = nil
  property value_files : Array(String)? = nil
  property secrets : Array(Secret) = Array(Secret).new
  property config_maps : Array(Secret) = Array(Secret).new

  property manifests : Array(String) = Array(String).new
  property before : Array(String) = Array(String).new
  property after : Array(String) = Array(String).new
  property ignore : Bool = false

  property run : Array(String) = Array(String).new
  property run_before : Array(String) = Array(String).new
  property run_after : Array(String) = Array(String).new

  def namespace!
    self.namespace.not_nil!
  end
end

class Secret
  include JSON::Serializable
  include YAML::Serializable

  property name : String
  property namespace : String? = nil
  property envs : Array(Env) = Array(Env).new
  property files : Array(FileElement) = Array(FileElement).new

  def namespace!
    self.namespace.not_nil!
  end
end

class Env
  include JSON::Serializable
  include YAML::Serializable

  property name : String
  property value : String?
  property env_name : String?
end

class FileElement
  include JSON::Serializable
  include YAML::Serializable

  property name : String
  property path : String
end
