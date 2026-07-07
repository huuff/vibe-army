{
  stdenvNoCC,
  lib,
}:

stdenvNoCC.mkDerivation {
  pname = "vibe-army";
  version = "0.1.0";

  src = lib.cleanSource ../.;

  installPhase = ''
    mkdir -p $out/share/vibe-army
    cp -r skills $out/share/vibe-army/
  '';

  meta = {
    description = "Agent setup: skills, templates, and scaffolding for AI coding harnesses";
  };
}
