module Kube::Helper::Secrets
  def apply_secret(secret : Secret)
    logger.debug { "Applying Secret: #{secret.name} namespace: #{secret.namespace}" }
    # create secret generic -n vault vault --from-file=config -o yaml --dry-run=client
    args = %w(create secret generic)
    build_secret_args(secret, args)

    with_kube_template_file(args) do |path|
      apply_file(path)
    end
  end

  def apply_configmap(secret : Secret)
    logger.debug { "Applying ConfigMap: #{secret.name} namespace: #{secret.namespace}" }

    # create secret generic -n vault vault --from-file=config -o yaml --dry-run=client
    args = %w(create configmap)
    build_secret_args(secret, args)

    with_kube_template_file(args) do |path|
      apply_file(path)
    end
  end

  def with_kube_template_file(args)
    begin
      resp = kubectl(args, silent: true)

      tempfile = File.tempfile(".yml") do |file|
        file.print(resp[:output])
      end

      yield tempfile.path
    rescue ex
      raise ex
    ensure
      tempfile.delete unless tempfile.nil?
    end
  end

  def from_literal_args(env) : String
    if !env.value.nil?
      "--from-literal=#{env.name}=#{env.value.not_nil!}"
    elsif !env.env_name.nil?
      "--from-literal=#{env.name}=#{ENV[env.env_name.not_nil!]}"
    else
      raise "Must set env value or env_name"
    end
  end

  def from_file_args(file) : String
    "--from-file=#{file.name}=#{get_path(file.path)}"
  end

  def build_secret_args(secret, args)
    args << "-n"
    args << secret.namespace
    args << secret.name

    unless secret.envs.empty?
      secret.envs.each do |env|
        args << from_literal_args(env)
      end
    end

    unless secret.files.empty?
      secret.files.each do |file|
        args << from_file_args(file)
      end
    end

    args << "--dry-run=client -o yaml"
  end
end
