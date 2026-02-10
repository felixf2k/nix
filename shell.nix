{ pkgs ? import <nixpkgs> {} }:
  pkgs.mkShell {
    nativeBuildInputs = with pkgs; [
      nodejs
      cypress
    ];
    buildInputs = [ pkgs.cargo pkgs.rustc ];
}
