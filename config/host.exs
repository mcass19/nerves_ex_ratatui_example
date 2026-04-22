import Config

# Add configuration that is only needed when running on the host here.

config :nerves_runtime,
  kv_backend:
    {Nerves.Runtime.KVBackend.InMemory,
     contents: %{
       "nerves_fw_active" => "a",
       "a.nerves_fw_architecture" => "generic",
       "a.nerves_fw_description" => "N/A",
       "a.nerves_fw_platform" => "host",
       "a.nerves_fw_version" => "0.0.0"
     }}

# While running the TUI examples on a laptop, ExRatatui owns the terminal
# via the alternate screen buffer. Any Logger write to stdout (especially
# noisy nerves_runtime / nerves_uevent crash reports on hosts that don't
# expose the expected sysfs / uevent interfaces) clobbers the TUI. Route
# Logger to a file so the terminal stays clean; on device (`target.exs`)
# the default handler is kept untouched.
config :logger, :default_handler,
  config: %{
    file: ~c"/tmp/nerves_ex_ratatui_example.log",
    filesync_repeat_interval: 5_000,
    file_check: 5_000,
    max_no_bytes: 10_485_760,
    max_no_files: 5
  }
