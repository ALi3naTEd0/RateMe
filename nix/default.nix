{ pkgs ? import <nixpkgs> {} }:

pkgs.callPackage ./flutter-app.nix {}
