{pkgs, ...}: {
  packages =
    [pkgs.rebar3]
    ++ (
      if (!pkgs.stdenv.isDarwin)
      then [pkgs.inotify-tools]
      else [pkgs.darwin.apple_sdk.frameworks.CoreServices]
    );

  languages.elixir.enable = true;
  languages.gleam.enable = true;
  languages.erlang.enable = true;
}
