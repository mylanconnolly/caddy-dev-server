# Caddy Dev Server

Mix tasks for installing and invoking [Caddy](https://caddyserver.com). This can
be useful if you wish to run multiple services behind the same domain name in
development or if you're just more familiar with Caddy than Phoenix's HTTPS
configuration. Running HTTPS in development can be useful as some SSO providers
disallow HTTP connections.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `caddy_dev_server` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:caddy_dev_server, "~> 0.1.0", only: :dev}
  ]
end
```

Once installed, change your `config/config.exs` to pick your Caddy version of
choice:

```elixir
config :caddy_dev_server, version: "2.10.0"
```

Now you can install Caddy with:

```bash
$ mix caddy_dev_server.install
```

You can invoke Caddy with:

```bash
$ mix caddy_dev_server default
```

If you are using Phoenix, check out the instructions below instead of running
Caddy manually.

## Adding to Phoenix

Add the following watcher to `config/dev.exs`:

```elixir
caddy: {CaddyDevServer, :install_and_run, [:default, ~w(--config Caddyfile)]}
```

## Configuring Caddy

You'll need a Caddyfile in order to run Caddy correctly. A reasonable default
for development is:

```caddyfile
phoenix.test {
	# Enable automatic HTTPS with internal certificates
	tls internal

	# Main application reverse proxy
	handle /* {
		reverse_proxy localhost:4000
	}
}
```

## Name resolution

You'll need to ensure that you're resolving whichever hostname you're listening
on to your localhost. This can be accomplished in a variety of ways. Editing
your `/etc/hosts` file in macOS / Linux / FreeBSD is an easy option. In Windows
the file path is `C:\Windows\System32\drivers\etc\hosts`.

If you have more robust needs (i.e., mapping a wildcard domain) a better option
might be using [dnsmasq](https://wiki.archlinux.org/title/Dnsmasq).
