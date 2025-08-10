{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  buildInputs = [
    pkgs.fuse3  # not libfuse3
    pkgs.bcc    # BPF Compiler Collection for Python/C
    pkgs.python3
    pkgs.pkg-config
    pkgs.gcc
    pkgs.rustc
    pkgs.cargo
  ];
}

