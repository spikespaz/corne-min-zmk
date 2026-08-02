{
  description = "ZMK firmware for corne-min";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    zmk-nix = {
      url = "github:lilyinstarlight/zmk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, zmk-nix }: let
    inherit (nixpkgs) lib;
    eachSystem = lib.genAttrs [ "aarch64-linux" "x86_64-linux" ];
    pkgsFor = eachSystem (system: import nixpkgs {
      localSystem.system = system;
      overlays = [
        (final: _: { zmkBuilders = zmk-nix.lib.buildersFor final; })
        self.overlays.default
      ];
    });

  in {
    overlays = {
      default = final: _: {
        corne-min-firmware = final.callPackage ./nix/default.nix {
          sourceRoot = self;
          inherit (final.zmkBuilders) buildKeyboard buildSplitKeyboard;
        };
      };
    };

    packages = eachSystem (system: let
      pkgs = pkgsFor.${system};
    in {
      # nix build .#firmware  (both halves; left is central)
      firmware = pkgs.corne-min-firmware;

      # nix build .#left / .#right  (individual halves)
      # nix build .#reset (clears left half BLE pairing state)
      inherit (pkgs.corne-min-firmware) left right reset;

      flash   = pkgs.callPackage "${zmk-nix}/nix/flash.nix" { firmware = pkgs.corne-min-firmware; };
      update  = pkgs.callPackage "${zmk-nix}/nix/update.nix" {};

      # nix build .#default  (both halves; left is central)
      default = pkgs.corne-min-firmware;
    });

    apps = eachSystem (system: {
      flash  = { type = "app"; program = lib.getExe self.packages.${system}.flash; };
      update = { type = "app"; program = lib.getExe self.packages.${system}.update; };

      default = self.apps.${system}.flash;
    });

    devShells = eachSystem (system: {
      default = pkgsFor.${system}.callPackage "${zmk-nix}/nix/shell.nix" {};
    });
  };
}
