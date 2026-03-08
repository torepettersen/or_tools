{
  description = "Elixir bindings for Google OR-Tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      devShells.x86_64-linux.default = pkgs.mkShell {
        packages = with pkgs; [
          elixir_1_19
          or-tools
        ];
        ORTOOLS_PREFIX = "${pkgs.or-tools}";
      };
    };
}
