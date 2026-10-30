{ inputs, lib, ... }:

{
  imports = [
    (inputs.ray-devenv + "/profiles/config.nix")
  ]
  ++ lib.optional (builtins.pathExists ./devenv.local.nix) ./devenv.local.nix;
}
