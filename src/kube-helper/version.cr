class Kube::Helper
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end
