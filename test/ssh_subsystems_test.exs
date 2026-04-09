defmodule SshSubsystemsTest do
  @moduledoc """
  Verifies the wiring between this project's TUI modules and the
  `ExRatatui.SSH.subsystem/1` helper that registers them with
  `nerves_ssh` (see `config/target.exs`).

  Tests run on the host target — they don't open an SSH socket, they
  just check that the spec tuples we install on the device have the
  shape OTP `:ssh` and `nerves_ssh` expect, and that each spec actually
  references one of our `ExRatatui.App` modules.
  """

  use ExUnit.Case, async: true

  describe "ExRatatui.SSH.subsystem/1 wrapping our TUIs" do
    test "SystemMonitorTui produces a valid subsystem_spec" do
      assert {name, {ExRatatui.SSH, init_args}} =
               ExRatatui.SSH.subsystem(SystemMonitorTui)

      assert is_list(name)
      assert List.to_string(name) == "Elixir.SystemMonitorTui"
      assert init_args[:mod] == SystemMonitorTui
    end

    test "LedTui produces a valid subsystem_spec" do
      assert {name, {ExRatatui.SSH, init_args}} =
               ExRatatui.SSH.subsystem(LedTui)

      assert is_list(name)
      assert List.to_string(name) == "Elixir.LedTui"
      assert init_args[:mod] == LedTui
    end

    test "the two TUIs land on different subsystem names" do
      {name_a, _} = ExRatatui.SSH.subsystem(SystemMonitorTui)
      {name_b, _} = ExRatatui.SSH.subsystem(LedTui)

      refute name_a == name_b
    end
  end

  describe "subsystem list as it appears in target.exs" do
    # NOTE: `NervesSSH.Options` is only available when the suite runs
    # under a real Nerves target (`MIX_TARGET=rpi*`). On `MIX_TARGET=host`
    # (the default for `mix test` on a laptop) it isn't on the code path,
    # so the validator branch below silently degrades to the shape-only
    # check. The "real" cross-check against `nerves_ssh`'s own option
    # parser only fires when CI builds firmware for an actual board.
    test "the list nerves_ssh receives passes its own validator" do
      # Mirror exactly what config/target.exs ships to :nerves_ssh.
      subsystems = [
        :ssh_sftpd.subsystem_spec(cwd: ~c"/"),
        ExRatatui.SSH.subsystem(SystemMonitorTui),
        ExRatatui.SSH.subsystem(LedTui)
      ]

      # nerves_ssh is loaded as a transitive dep of nerves_pack — only
      # available when its application code is on the path. Skip the
      # validator check on hosts where it isn't. apply/3 keeps the
      # reference dynamic so the host compiler doesn't warn.
      options_mod = NervesSSH.Options

      if Code.ensure_loaded?(options_mod) do
        opts = apply(options_mod, :new, [[subsystems: subsystems]])
        # `:ssh_sftpd` ships with OTP, our two specs come from
        # ExRatatui — none should get filtered out as malformed.
        assert length(opts.subsystems) == 3
      end

      # Sanity-check the shape regardless of nerves_ssh availability:
      # every entry must be a `{charlist, {module, init_args}}` tuple.
      for {name, {mod, init}} <- subsystems do
        assert is_list(name)
        assert is_atom(mod)
        assert is_list(init)
      end
    end

    test "all three subsystems have unique names (no collisions)" do
      subsystems = [
        :ssh_sftpd.subsystem_spec(cwd: ~c"/"),
        ExRatatui.SSH.subsystem(SystemMonitorTui),
        ExRatatui.SSH.subsystem(LedTui)
      ]

      names = Enum.map(subsystems, &elem(&1, 0))
      assert names == Enum.uniq(names)
    end
  end
end
