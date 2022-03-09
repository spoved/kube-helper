require "yaml"
require "json"

class Config
  include JSON::Serializable
  include YAML::Serializable

  property helm : Helm = Helm.new
  property secrets : Array(Secret) = Array(Secret).new
  property config_maps : Array(Secret) = Array(Secret).new
  property namespaces : Array(Namespace) = Array(Namespace).new
  property manifests : Array(String) = Array(String).new
  property apps : Array(AppOptions) = Array(AppOptions).new
  property groups : Array(Group) = Array(Group).new
  property context : String? = nil

  def initialize; end
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

  def namespace : Namespace
    if self.default_namespace.nil?
      Namespace.new(self.name, self.project)
    else
      Namespace.new(self.default_namespace.not_nil!, nil)
    end
  end
end

class Namespace
  include JSON::Serializable
  include YAML::Serializable
  property name : String
  property project : String? = nil
  property istio : Bool = false

  def initialize(@name, @project);end
end

class Helm
  include JSON::Serializable
  include YAML::Serializable
  property repos : Repos = Repos.new
  def initialize; end
end

alias Values=YAML::Any
alias Repos=Hash(String, String)

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
  property values : Values? = nil
  property secrets : Array(Secret) = Array(Secret).new
  property config_maps : Array(Secret) = Array(Secret).new

  property manifests : Array(String) = Array(String).new
  property before : Array(String) = Array(String).new
  property after : Array(String) = Array(String).new
  property ignore : Bool = false

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
