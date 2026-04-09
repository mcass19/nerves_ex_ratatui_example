import Config

# Use Ringlogger as the logger backend and remove :console.
# See https://hexdocs.pm/ring_logger/readme.html for more information on
# configuring ring_logger.

config :logger, backends: [RingLogger]

# Use shoehorn to start the main application. See the shoehorn
# library documentation for more control in ordering how OTP
# applications are started and handling failures.

config :shoehorn, init: [:nerves_runtime, :nerves_pack]

# Enable the system startup guard to check that all OTP applications
# started. If they didn't and you're on a Nerves system that supports
# test runs of new firmware, the firmware will automatically roll
# back to the previous version. Delete this if implementing your own
# way of validating that firmware is good.
config :nerves_runtime, startup_guard_enabled: true

# Erlinit can be configured without a rootfs_overlay. See
# https://github.com/nerves-project/erlinit/ for more information on
# configuring erlinit.

# Advance the system clock on devices without a real-time clock.
config :nerves, :erlinit, update_clock: true

# Configure the device for SSH IEx prompt access and firmware updates
#
# * See https://hexdocs.pm/nerves_ssh/readme.html for general SSH configuration
# * See https://hexdocs.pm/ssh_subsystem_fwup/readme.html for firmware updates
#
# In addition to the standard IEx shell, both example TUIs are registered
# as SSH subsystems pointing at `ExRatatui.SSH`. From any client with an
# authorized key:
#
#     ssh -t nerves@nerves.local -s Elixir.SystemMonitorTui
#     ssh -t nerves@nerves.local -s Elixir.LedTui
#
# The `-t` is **required** for interactive TUI use — OpenSSH does not
# allocate a PTY by default for `-s` (subsystem) mode, so without it the
# local terminal stays in cooked mode and keystrokes get line-buffered
# and echoed locally instead of flowing to the TUI.
#
# The TUI runs entirely on the device — the SSH channel just shuttles
# render bytes to your terminal and key events back. Plain
# `ssh nerves@nerves.local` still drops you into the regular IEx shell,
# so you keep the manual `iex> SystemMonitorTui.run()` path too.
#
# Note: each subsystem entry below is the literal tuple
# `ExRatatui.SSH.subsystem/1` would return — see its docs for the shape.
# We inline it here on purpose: when `MIX_TARGET=rpi4 mix compile` (or
# any other non-host target) loads this file, Mix hasn't compiled deps
# for the target yet, so calling `ExRatatui.SSH.subsystem(...)` blows up
# with "module ExRatatui.SSH is not available". Module *atoms* work fine
# without the module being loaded — function calls don't.
#
# The `subsystem: true` flag tells the channel handler it was dispatched
# via OTP's `:subsystems` path. OTP consumes the `{:subsystem, ...}`
# request internally when it matches a registered name, so the handler
# only ever sees `{:ssh_channel_up, ...}` — without this flag, the
# handler would wait forever for a shell request that never comes.

keys =
  System.user_home!()
  |> Path.join(".ssh/id_{rsa,ecdsa,ed25519}.pub")
  |> Path.wildcard()

if keys == [],
  do:
    Mix.raise("""
    No SSH public keys found in ~/.ssh. An ssh authorized key is needed to
    log into the Nerves device and update firmware on it using ssh.
    See your project's config.exs for this error message.
    """)

config :nerves_ssh,
  authorized_keys: Enum.map(keys, &File.read!/1),
  subsystems: [
    :ssh_sftpd.subsystem_spec(cwd: ~c"/"),
    {~c"Elixir.SystemMonitorTui", {ExRatatui.SSH, [mod: SystemMonitorTui, subsystem: true]}},
    {~c"Elixir.LedTui", {ExRatatui.SSH, [mod: LedTui, subsystem: true]}}
  ]

# Configure the network using vintage_net
#
# Update regulatory_domain to your 2-letter country code E.g., "US"
#
# See https://github.com/nerves-networking/vintage_net for more information
config :vintage_net,
  regulatory_domain: "00",
  config: [
    {"usb0", %{type: VintageNetDirect}},
    {"eth0",
     %{
       type: VintageNetEthernet,
       ipv4: %{method: :dhcp}
     }},
    {"wlan0", %{type: VintageNetWiFi}}
  ]

config :mdns_lite,
  hosts: [:hostname, "nerves"],
  ttl: 120,
  services: [
    %{
      protocol: "ssh",
      transport: "tcp",
      port: 22
    },
    %{
      protocol: "sftp-ssh",
      transport: "tcp",
      port: 22
    },
    %{
      protocol: "epmd",
      transport: "tcp",
      port: 4369
    }
  ]
