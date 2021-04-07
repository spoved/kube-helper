require "./kube-helper/*"
require "./kube/*"

WORKDIR = FileUtils.pwd
OPTIONS = Hash(Symbol, Bool | String | Nil | Array(String)){
  :quiet       => false,
  :verbose     => false,
  :debug       => false,
  :all         => false,
  :manifests   => false,
  :namespaces  => false,
  :names       => Array(String).new,
  :name_filter => false,
  :secrets     => false,
  :config_maps => false,
  :apps        => false,
  :delete      => false,
  :groups      => false,
  :group_names => Array(String).new,
  :list        => false,
  :workdir     => "./",
}

KUBECONFIG = ENV.fetch("KUBECONFIG", File.join(Path.home, ".kube/config"))
KUBECMD    = "kubectl --kubeconfig #{KUBECONFIG}"

Kube::Helper.new.run!
