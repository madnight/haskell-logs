{ mkDerivation, aeson, base, containers, ghcjs-base, miso
, network-uri, servant, stdenv
}:
mkDerivation {
  pname = "app";
  version = "0.1.0.0";
  src = ./.;
  isLibrary = false;
  isExecutable = true;
  executableHaskellDepends = [
    aeson base containers ghcjs-base miso network-uri servant
  ];
  description = "First miso app";
  license = stdenv.lib.licenses.mit;
}
