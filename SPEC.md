# Deployment YAML File Specification

[Full Example](#full-example)

## Top level members

| key                                 | type               | description                                                         |
| ----------------------------------- | ------------------ | ------------------------------------------------------------------- |
| [`helm`](#helm)                     | Object             | Object containing helm configurations                               |
| [`manifests`](#configmap--secret)   | Array(String)      | An array of strings of manifest paths                               |
| [`config_maps`](#configmap--secret) | Array(Object)      | An array of `ConfigMap` objects                                     |
| [`secrets`](#configmap--secret)     | Array(Object)      | An array of `Secret` objects                                        |
| [`namespaces`](#namespace)          | Array(Object)      | An array of `Namespace` objects                                     |
| [`groups`](#group)                  | Array(GroupObject) | A list of [`Group`](#group-object-definition) objects               |
| [`apps`](#applications)             | Array(Object)      | An array of [`Application`](#application-object-definition) objects |

```yaml
helm: {}
manifests: []
config_maps: []
secrets: []
namespaces: []
groups: {}
apps: []
```

## Object Definitions

### Helm

contains a list of helm repos that are needed. these will be added to your local helm environment when `--helm` is passed.

```yaml
helm:
  repos:
    elastic: https://helm.elastic.co
    rancher-latest: https://releases.rancher.com/server-charts/latest
    bitnami: https://charts.bitnami.com/bitnami
    grafana: https://grafana.github.io/helm-charts
    longhorn: https://charts.longhorn.io
```

### Manifests

A list of local paths or urls of `yaml` files to apply.

**Note** Only the top level manifests are applied without a namespace.

```yaml
manifests:
  - https://github.com/jetstack/cert-manager/releases/download/v1.2.0/cert-manager.yaml
  - manifests/cert-manager/cluster-issuers.yml
```

### ConfigMap / Secret

A `ConfigMap` and `Secret` object are defined the same. However they are translated into k8s `ConfigMap` and `Secret` objects respectively.
Sub keys `files` and `envs` define the name and content of the key/value pairs.

```yaml
secrets:
  - name: my-secret-database-config
    namespace: database
    files:
      - name: secret-config.yml
        path: apps/database/secret-config.yml
      - name: credentials
        path: apps/database/credentials.file
config_map:
  - name: my-database-config
    files:
      - name: config.yml
        path: apps/database/config.yml
  - name: database-envs
    envs:
      - name: ENVIRONMENT
        value: production
      - name: MEMLIMIT
        value: high
```

### Namespace

A `Namespace` object defines any namespaces you wish to be created. It also applies metadata tags for management with [Rancher](https://rancher.com/). If you are not using Rancher, then there is no reason to use this.

```yaml
namespaces:
  - name: minio
    # This defines the rancher project to add this namespace too
    project: p-2bxsm
  - name: vault
    project: p-2bxsm
    # This will add istio annotations to the namespace
    istio: true
```

### Applications

A `Application` object defines a helm chart instalation or a logical grouping of `ConfigMap`, `Secret`, or `Manifests` to apply.

#### Application Object Definition

| name          | type               | required | description                                                                         |
| ------------- | ------------------ | -------- | ----------------------------------------------------------------------------------- |
| `name`        | String             | true     | This is the name of app used for filtering                                          |
| `namespace`   | String             | true     | The namepace all resources will be placed into. Will create it if it doesnt exist.  |
| `config_maps` | Array(Object)      | false    | An array of `ConfigMap` objects                                                     |
| `secrets`     | Array(Object)      | false    | An array of `Secret` objects                                                        |
| `manifests`   | Array(String)      | false    | An array of strings of manifest paths                                               |
| `before`      | Array(String)      | false    | Same as `manifests` but will be applied first                                       |
| `after`       | Array(String)      | false    | Same as `manifests` but will be applied last                                        |
| `chart_path`  | String             | false    | This can be a local path to a helm directory or tar file.                           |
| `chart_url`   | String             | false    | This can be a http url to a helm tar file                                           |
| `version`     | String             | false    | The chart version to specify                                                        |
| `values`      | (String \| Object) | false    | This can be a path to a file to be used as a values.yml or the raw yaml data itself |
| `ignored`     | Bool               | false    | If set to true, it and all sub resources will be ignored by the tool                |

#### Helm Charts

A helm chart application can look like this:

```yaml
apps:
  - name: rancher
    ignore: false
    chart: rancher-latest/rancher
    namespace: cattle-system
    values:
      hostname: rancher.mydomain.com
      ingress:
        tls:
          source: secret
        extraAnnotations:
          cert-manager.io/cluster-issuer: letsencrypt-prod
          nginx.ingress.kubernetes.io/configuration-snippet: |
            more_set_headers "X-Robots-Tag: noindex";
  - name: sidekiq-web
    namespace: fulgurite-sidekiq
    chart_path: ./charts/app/
    values: apps/fulgurite/sidekiq/sidekiq-web.yml

  - name: vault
    namespace: vault
    chart_path: apps/vault/v0.5.0.tar.gz
```

The main values required for a helm chart app are:

- `chart` - the name of the helm chart. i.e "stable/nfs-server-provisioner"
- `chart_path` - the local path of the chart (dir or tgz) relative to the `deployment.yml`
- `chart_url` - the http(s) url to pull the chart tgz

The `values` is not required if the charts default values are wanted.

### Non-Helm

Applications can still be defined without a helm chart. Any

```yaml
apps:
  - name: minio-operator
    namespace: minio-operator
    secrets:
      - name: mysecret
        namespace: minio-operator
        envs:
          - name: MYKEY
            value: value
    manifests:
      # - https://raw.githubusercontent.com/minio/minio-operator/master/minio-operator.yaml
      - apps/operators/minio/operator.yml
```

### Group

A `Group` object is a logical grouping of `apps` other resources for oganizational purposes.

#### Group Object Definition

| name                | type               | required | description                                                          |
| ------------------- | ------------------ | -------- | -------------------------------------------------------------------- |
| `name`              | String             | true     | Name of the group                                                    |
| `default_namespace` | String             | false    | The default namespace to use for sub resources                       |
| `config_maps`       | Array(Object)      | false    | An array of `ConfigMap` objects                                      |
| `secrets`           | Array(Object)      | false    | An array of `Secret` objects                                         |
| `before`            | Array(String)      | false    | Same as `manifests` but will be applied before children              |
| `after`             | Array(String)      | false    | Same as `manifests` but will be applied after children               |
| `ignored`           | Bool               | false    | If set to true, it and all sub resources will be ignored by the tool |
| `apps`              | Array(Application) | false    | An array of `Application` objects                                    |

```yaml
groups:
  production:
    apps:
      - name: sidekiq-web
        namespace: fulgurite-sidekiq
        chart_path: ./charts/app/
        values: apps/fulgurite/sidekiq/sidekiq-web.yml
      - name: vault
        namespace: vault
        chart_path: apps/vault/v0.5.0.tar.gz
  development:
    apps:
      - name: sidekiq-web
        namespace: development
        chart_path: ./charts/app/
        values: apps/fulgurite/sidekiq/sidekiq-web.yml
      - name: vault
        namespace: development
        chart_path: apps/vault/v0.5.0.tar.gz
```

## Full Example

```yaml
helm:
  repos:
    elastic: https://helm.elastic.co
    rancher-latest: https://releases.rancher.com/server-charts/latest
    bitnami: https://charts.bitnami.com/bitnami
    grafana: https://grafana.github.io/helm-charts
    longhorn: https://charts.longhorn.io
manifests:
  - https://github.com/jetstack/cert-manager/releases/download/v1.2.0/cert-manager.yaml
  - manifests/cert-manager/cluster-issuers.yml

secrets:
  - name: my-secret-database-config
    namespace: database
    files:
      - name: secret-config.yml
        path: apps/database/secret-config.yml
      - name: credentials
        path: apps/database/credentials.file

config_map:
  - name: my-database-config
    files:
      - name: config.yml
        path: apps/database/config.yml
  - name: database-envs
    envs:
      - name: ENVIRONMENT
        value: production
      - name: MEMLIMIT
        value: high

namespaces:
  - name: minio
    project: p-2bxsm
  - name: vault
    project: p-2bxsm
    istio: true

groups:
  production:
    apps:
      - name: sidekiq-web
        namespace: production
        chart_path: ./charts/app/
        values: apps/fulgurite/sidekiq/sidekiq-web.yml
      - name: vault
        namespace: production
        chart_path: apps/vault/v0.5.0.tar.gz
  development:
    apps:
      - name: sidekiq-web
        namespace: development
        chart_path: ./charts/app/
        values: apps/fulgurite/sidekiq/sidekiq-web.yml
      - name: vault
        namespace: development
        chart_path: apps/vault/v0.5.0.tar.gz

apps:
  - name: minio-operator
    namespace: minio-operator
    secrets:
      - name: mysecret
        namespace: minio-operator
        envs:
          - name: MYKEY
            value: value
    manifests:
      # - https://raw.githubusercontent.com/minio/minio-operator/master/minio-operator.yaml
      - apps/operators/minio/operator.yml
```
