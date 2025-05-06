defmodule CaddyDevServerTest do
  use ExUnit.Case, async: true

  @version CaddyDevServer.latest_version()

  setup do
    Application.put_env(:caddy_dev_server, :version, @version)

    :ok
  end

  test "run on default" do
    assert ExUnit.CaptureIO.capture_io(fn ->
             assert CaddyDevServer.run(:default, ["-v"]) == 0
           end) =~ @version
  end

  test "run on profile" do
    assert ExUnit.CaptureIO.capture_io(fn ->
             assert CaddyDevServer.run(:another, []) == 0
           end) =~ @version
  end

  test "updates on install" do
    Application.put_env(:caddy_dev_server, :version, "2.9.0")
    Mix.Task.rerun("caddy_dev_server.install", ["--if-missing"])

    assert ExUnit.CaptureIO.capture_io(fn ->
             assert CaddyDevServer.run(:default, ["-v"]) == 0
           end) =~ "2.9.0"

    Application.delete_env(:caddy_dev_server, :version)

    Mix.Task.rerun("caddy_dev_server.install", ["--if-missing"])

    assert ExUnit.CaptureIO.capture_io(fn ->
             assert CaddyDevServer.run(:default, ["-v"]) == 0
           end) =~ @version
  end
end
