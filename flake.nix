{
  description = "CLI tool for querying iHerb product data via a headless Chromium";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          chromium = if pkgs.stdenv.isDarwin then null else pkgs.chromium;
        in
        rec {
          iherb-cli = pkgs.rustPlatform.buildRustPackage {
            pname = "iherb-cli";
            version = (builtins.fromTOML (builtins.readFile ./Cargo.toml)).package.version;
            src = self;
            cargoLock.lockFile = ./Cargo.lock;

            nativeBuildInputs = with pkgs; [ pkg-config installShellFiles ] ++ lib.optional (chromium != null) makeWrapper;
            buildInputs = with pkgs; [ openssl ];

            # network-dependent tests can't run in the sandbox
            doCheck = false;

            postInstall = ''
              installShellCompletion --cmd iherb-cli --zsh <(COMPLETE=zsh "$out/bin/iherb-cli")
            '';

            postFixup = pkgs.lib.optionalString (chromium != null) ''
              wrapProgram $out/bin/iherb-cli \
                --set-default IHERB_BROWSER_PATH ${pkgs.lib.getExe chromium}
            '';

            meta = with pkgs.lib; {
              description = "Query iHerb product data from the command line (headless-browser scraper, no API key)";
              homepage = "https://github.com/rivavolt/iherb-cli";
              license = licenses.mit;
              mainProgram = "iherb-cli";
            };
          };
          default = iherb-cli;
        });

      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          chromium = if pkgs.stdenv.isDarwin then null else pkgs.chromium;
        in
        {
          # Binaries built in the shell are unwrapped, so without IHERB_BROWSER_PATH
          # they fall back to downloading Chrome for Testing, which ships no aarch64
          # Linux build and dies with "Exec format error".
          default = pkgs.mkShell ({
            inputsFrom = [ self.packages.${system}.iherb-cli ];
            packages = with pkgs; [ rust-analyzer clippy rustfmt ]
              ++ lib.optional (chromium != null) chromium;
          } // pkgs.lib.optionalAttrs (chromium != null) {
            IHERB_BROWSER_PATH = pkgs.lib.getExe chromium;
          });
        });
    };
}
