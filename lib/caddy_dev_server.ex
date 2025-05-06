defmodule CaddyDevServer do
  # https://github.com/caddyserver/caddy/releases
  @latest_version "2.10.0"

  @moduledoc """
  CaddyDevServer is an installer and runner for [caddy](https://caddyserver.com/).

  ## Profiles

  You can define multiple tailwind profiles. By default, there is a
  profile called `:default` which you can configure its args, current
  directory and environment:

      config :caddy_dev_server,
        version: "#{@latest_version}",
        default: [
          args: ~w(--config Caddyfile)
        ]

  ## Caddy configuration

  There are four global configurations for the tailwind application:

    * `:version` - the expected tailwind version

    * `:version_check` - whether to perform the version check or not.
      Useful when you manage the tailwind executable with an external
      tool (eg. npm)

    * `:path` - the path to find the caddy executable at. By
      default, it is automatically downloaded and placed inside
      the `_build` directory of your current app

    * `:target` - the target architecture for the tailwind executable.
      For example `"linux_arm64"`. By default, it is automatically detected
      based on system information.

  Overriding the `:path` is not recommended, as we will automatically
  download and manage `caddy` for you. But in case you can't download
  it (for example, GitHub behind a proxy), you may want to
  set the `:path` to a configurable system location.

  For instance, you can install `caddy` globally with `brew`:

      $ brew install caddy

  Once you find the location of the executable, you can store it in a
  `MIX_CADDY_PATH` environment variable, which you can then read in
  your configuration file:

      config :caddy_dev_server, path: System.get_env("MIX_CADDY_PATH")

  """

  use Application

  require Logger

  @doc false
  def start(_, _) do
    if Application.get_env(:caddy_dev_server, :version_check, true) do
      unless Application.get_env(:caddy_dev_server, :version) do
        Logger.warning("""
        caddy version is not configured. Please set it in your config files:

            config :caddy_dev_server, :version, "#{latest_version()}"
        """)
      end

      configured_version = configured_version()

      case bin_version() do
        {:ok, ^configured_version} ->
          :ok

        {:ok, version} ->
          Logger.warning("""
          Outdated caddy version. Expected #{configured_version}, got #{version}. \
          Please run `mix caddy_dev_server.install` or update the version in your config files.\
          """)

        :error ->
          :ok
      end
    end

    Supervisor.start_link([], strategy: :one_for_one)
  end

  @doc false
  # Latest known version at the time of publishing.
  def latest_version, do: @latest_version

  @doc """
  Returns the configured tailwind version.
  """
  def configured_version do
    Application.get_env(:caddy_dev_server, :version, latest_version())
  end

  @doc """
  Returns the configured tailwind target. By default, it is automatically detected.
  """
  def configured_target do
    Application.get_env(:caddy_dev_server, :target, target())
  end

  @doc """
  Returns the configuration for the given profile.

  Returns nil if the profile does not exist.
  """
  def config_for!(profile) when is_atom(profile) do
    Application.get_env(:caddy_dev_server, profile) ||
      raise ArgumentError, """
      unknown caddy profile. Make sure the profile is defined in your config/config.exs file, such as:

          config :caddy_dev_server,
            version: "#{@latest_version}",
            #{profile}: [
              args: ~w(--config Caddyfile)
            ]
      """
  end

  @doc """
  Returns the path to the executable.

  The executable may not be available if it was not yet installed.
  """
  def bin_path do
    name = "caddy-#{configured_target()}"

    Application.get_env(:caddy_dev_server, :path) ||
      if Code.ensure_loaded?(Mix.Project) do
        Path.join(Path.dirname(Mix.Project.build_path()), name)
      else
        Path.expand("_build/#{name}")
      end
  end

  @doc """
  Returns the version of the tailwind executable.

  Returns `{:ok, version_string}` on success or `:error` when the executable
  is not available.
  """
  def bin_version do
    path = bin_path()

    with true <- File.exists?(path),
         {out, 0} <- System.cmd(path, ["-v"]),
         [vsn] <- Regex.run(~r/v([^\s]+)\s+/, out, capture: :all_but_first) do
      {:ok, vsn}
    else
      _ -> :error
    end
  end

  @doc """
  Runs the given command with `args`.

  The given args will be appended to the configured args.
  The task output will be streamed directly to stdio. It
  returns the status of the underlying call.
  """
  def run(profile, extra_args) when is_atom(profile) and is_list(extra_args) do
    config = config_for!(profile)
    args = config[:args] || []
    env = Keyword.get(config, :env, %{})

    opts = [
      env: env,
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true
    ]

    bin_path()
    |> System.cmd(args ++ extra_args, opts)
    |> elem(1)
  end

  @doc """
  Installs, if not available, and then runs `caddy`.

  Returns the same as `run/2`.
  """
  def install_and_run(profile, args) do
    unless File.exists?(bin_path()) do
      install()
    end

    run(profile, args)
  end

  @doc """
  The default URL to install Caddy from.
  """
  def default_base_url do
    "https://github.com/caddyserver/caddy/releases/download/v$version/caddy_$version_$target.$ext"
  end

  @doc """
  Installs caddy with `configured_version/0`.
  """
  def install(base_url \\ default_base_url()) do
    url = get_url(base_url)
    bin_path = bin_path()
    tar = fetch_body!(url)
    binary = extract_binary!(tar)
    File.mkdir_p!(Path.dirname(bin_path))

    # MacOS doesn't recompute code signing information if a binary
    # is overwritten with a new version, so we force creation of a new file
    if File.exists?(bin_path) do
      File.rm!(bin_path)
    end

    File.write!(bin_path, binary, [:binary])
    File.chmod(bin_path, 0o755)
  end

  defp extract_binary!(tar) do
  end

  # Available targets:
  #  caddy-freebsd_arm64
  #  caddy-freebsd_amd64
  #  caddy-linux_arm64
  #  caddy-linux_amd64
  #  caddy-linux_armv7
  #  caddy-mac_arm64
  #  caddy-mac_amd64
  #  caddy-windows_amd64.exe
  defp target do
    arch_str = :erlang.system_info(:system_architecture)
    target_triple = arch_str |> List.to_string() |> String.split("-")

    {arch, abi} =
      case target_triple do
        [arch, _vendor, _system, abi] -> {arch, abi}
        [arch, _vendor, abi] -> {arch, abi}
        [arch | _] -> {arch, nil}
      end

    case {:os.type(), arch, abi, :erlang.system_info(:wordsize) * 8} do
      {{:win32, _}, _arch, _abi, 64} ->
        "windows_amd64.exe"

      {{:unix, :darwin}, arch, _abi, 64} when arch in ~w(arm aarch64) ->
        "mac_arm64"

      {{:unix, :darwin}, "x86_64", _abi, 64} ->
        "mac_amd64"

      {{:unix, :freebsd}, "aarch64", _abi, 64} ->
        "freebsd_arm64"

      {{:unix, :freebsd}, arch, _abi, 64} when arch in ~w(x86_64 amd64) ->
        "freebsd_amd64"

      {{:unix, :linux}, "aarch64", _abi, 64} ->
        "linux_arm64"

      {{:unix, :linux}, "arm", _abi, 32} ->
        "linux_armv7"

      {{:unix, :linux}, "armv7" <> _, _abi, 32} ->
        "linux_armv7"

      {{:unix, _osname}, arch, _abi, 64} when arch in ~w(x86_64 amd64) ->
        "linux_amd64"

      {_os, _arch, _abi, _wordsize} ->
        raise "caddy is not available for architecture: #{arch_str}"
    end
  end

  defp fetch_body!(url, retry \\ true) when is_binary(url) do
    scheme = URI.parse(url).scheme
    url = String.to_charlist(url)
    Logger.debug("Downloading caddy from #{url}")

    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    if proxy = proxy_for_scheme(scheme) do
      %{host: host, port: port} = URI.parse(proxy)
      Logger.debug("Using #{String.upcase(scheme)}_PROXY: #{proxy}")
      set_option = if "https" == scheme, do: :https_proxy, else: :proxy
      :httpc.set_options([{set_option, {{String.to_charlist(host), port}, []}}])
    end

    http_options =
      [
        ssl: [
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          depth: 2,
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ],
          versions: protocol_versions()
        ]
      ]
      |> maybe_add_proxy_auth(scheme)

    options = [body_format: :binary]

    case {retry, :httpc.request(:get, {url, []}, http_options, options)} do
      {_, {:ok, {{_, 200, _}, _headers, body}}} ->
        body

      {_, {:ok, {{_, 404, _}, _headers, _body}}} ->
        raise """
        The caddy binary couldn't be found at: #{url}

        This could mean that you're trying to install a version that does not support the detected
        target architecture.

        You can see the available files for the configured version at:

        https://github.com/caddyserver/caddy/releases/tag/v#{configured_version()}
        """

      {true, {:error, {:failed_connect, [{:to_address, _}, {inet, _, reason}]}}}
      when inet in [:inet, :inet6] and
             reason in [:ehostunreach, :enetunreach, :eprotonosupport, :nxdomain] ->
        :httpc.set_options(ipfamily: fallback(inet))
        fetch_body!(to_string(url), false)

      other ->
        raise """
        Couldn't fetch #{url}: #{inspect(other)}

        This typically means we cannot reach the source or you are behind a proxy.
        You can try again later and, if that does not work, you might:

          1. If behind a proxy, ensure your proxy is configured and that
             your certificates are set via OTP ca certfile overide via SSL configuration.

          2. Manually download the executable from the URL above and
             place it inside "_build/caddy-#{configured_target()}"

          3. Install and use Caddy from Homebrew. See our module documentation
             to learn more: https://hexdocs.pm/caddy_dev_server
        """
    end
  end

  defp fallback(:inet), do: :inet6
  defp fallback(:inet6), do: :inet

  defp proxy_for_scheme("http") do
    System.get_env("HTTP_PROXY") || System.get_env("http_proxy")
  end

  defp proxy_for_scheme("https") do
    System.get_env("HTTPS_PROXY") || System.get_env("https_proxy")
  end

  defp maybe_add_proxy_auth(http_options, scheme) do
    case proxy_auth(scheme) do
      nil -> http_options
      auth -> [{:proxy_auth, auth} | http_options]
    end
  end

  defp proxy_auth(scheme) do
    with proxy when is_binary(proxy) <- proxy_for_scheme(scheme),
         %{userinfo: userinfo} when is_binary(userinfo) <- URI.parse(proxy),
         [username, password] <- String.split(userinfo, ":") do
      {String.to_charlist(username), String.to_charlist(password)}
    else
      _ -> nil
    end
  end

  defp protocol_versions do
    if otp_version() < 25, do: [:"tlsv1.2"], else: [:"tlsv1.2", :"tlsv1.3"]
  end

  defp otp_version do
    :erlang.system_info(:otp_release) |> List.to_integer()
  end

  defp get_url(base_url) do
    target = configured_target()

    base_url
    |> String.replace("$version", configured_version())
    |> String.replace("$target", target)
    |> String.replace("$ext", if(String.contains?(target, "windows"), do: "zip", else: "tar.gz"))
  end
end
