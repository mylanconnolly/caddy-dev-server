defmodule Mix.Tasks.CaddyDevServer.Install do
  @moduledoc """
  Installs Caddy executable and assets.

      $ mix caddy_dev_server.install
      $ mix caddy_dev_server.install --if-missing

  By default, it installs #{CaddyDevServer.latest_version()} but you
  can configure it in your config files, such as:

      config :caddy_dev_server, :version, "#{CaddyDevServer.latest_version()}"

  To install the Caddy binary from a custom URL (e.g. if your platform isn't
  officially supported by Caddy), you can supply a third party path to the
  binary (beware that we cannot guarantee the compatibility of any third party
  executable):

  ```bash
  $ mix caddy_dev_server.install https://hostname.com/path/to/caddy.tar.gz
  ```

  ## Options

      * `--runtime-config` - load the runtime configuration
        before executing command

      * `--if-missing` - install only if the given version
        does not exist
  """

  @shortdoc "Installs Caddy executable"
  @compile {:no_warn_undefined, Mix}

  use Mix.Task

  @impl true
  def run(args) do
    valid_options = [runtime_config: :boolean, if_missing: :boolean]

    {opts, base_url} =
      case OptionParser.parse_head!(args, strict: valid_options) do
        {opts, []} ->
          {opts, CaddyDevServer.default_base_url()}

        {opts, [base_url]} ->
          {opts, base_url}

        {_, _} ->
          Mix.raise("""
          Invalid arguments to caddy_dev_server.install, expected one of:

          mix caddy_dev_server.install
          mix caddy_dev_server.install 'https://github.com/caddyserver/caddy/releases/download/v$version/caddy_$version_$target.$ext'
          mix caddy_dev_server.install --runtime-config
          mix caddy_dev_server.install --if-missing
          """)
      end

    if opts[:runtime_config], do: Mix.Task.run("app.config")

    if opts[:if_missing] && latest_version?() do
      :ok
    else
      if function_exported?(Mix, :ensure_application!, 1) do
        Mix.ensure_application!(:inets)
        Mix.ensure_application!(:ssl)
      end

      Mix.Task.run("loadpaths")
      CaddyDevServer.install(base_url)
    end
  end

  defp latest_version?() do
    version = CaddyDevServer.configured_version()
    match?({:ok, ^version}, CaddyDevServer.bin_version())
  end
end
