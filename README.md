# kube-helper

This is a basic CLI tool that asists in applying k8s configurations easily. Configuration is applied via the schema defined in a `deployment.yml` file.

## Installation

### Requirements

- kubectl (>= 1.18)
- helm (>= 3.0)
- crystal (>= 1.0.0)

### Build

```shell
git clone https://github.com/spoved/kube-helper.git
cd kube-helper
shards build --ignore-crystal-version
```

## Usage

```shell
$ ./bin/kube-helper --help
Usage: kube-helper [arguments]

    -h, --help                       Show this help
    --version                        Print version and exit

Config Flags:
    -w DIR, --workdir DIR            Working directory. default: "./"
    -f FILE, --file FILE             Name of config file. default: deployment.yml
    --kubeconfig FILE                Path to the kube config file. default: /Users/homans/.kube/config

Logging Flags:
    -q, --quiet                      Log errors only
    -v, --verbose                    Log verbose
    -d, --debug                      Log debug

Runtime Flags:
  general options:
    --all                            Apply all updates/changes
    -l, --list                       List groups and apps and exit
  apply/create specific resources:
    --ns, --namespaces               Create namespaces
    -m, --manifests                  Apply manifests
    -s, --secrets                    Apply secrets
    -c, --configmaps                 Apply configmaps
  filter resources:
    --groups                         Update only groups
    --apps                           Update only apps
    -g NAME, --group NAME            Only apply changes to specified group with NAME. (accepts multiple)
    -n NAME, --name NAME             Only apply changes to apps with this name.       (accepts multiple)
  local environment config:
    --helm                           Update helm repos
  destructive actions:
    --delete                         Delete app manifests
```

## Contributing

1. Fork it (<https://github.com/spoved/kube-helper/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Holden Omans](https://github.com/kalinon) - creator and maintainer
