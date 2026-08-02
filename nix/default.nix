{
  lib,
  sourceRoot ? ../.,
  buildKeyboard,
  buildSplitKeyboard,
  python3Packages
}: let

  filteredSrc = lib.sourceFilesBySuffices sourceRoot [
    ".board" ".cmake" ".conf" ".defconfig" ".dts" ".dtsi"
    ".json" ".keymap" ".overlay" ".shield" ".yml" "_defconfig"
  ];

  zephyrDepsHash = "sha256-qB4DEL4UldZoZc6C60reewAcwfbfR7SLuK2grfyMZuY=";

  # grpcio-tools ≥1.82 dropped setuptools from propagatedBuildInputs;
  # setuptools ≥82 removed pkg_resources. Inject setuptools 80.9.0 via
  # nativeBuildInputs so the nanopb generator can import pkg_resources.
  setuptools-compat = python3Packages.setuptools.overridePythonAttrs (_: rec {
    version = "80.9.0";
    src = python3Packages.fetchPypi {
      pname = "setuptools";
      inherit version;
      hash = "sha256-82tHQC7N52jb+vxG6OQge0NgxlTx87uER18KKGKPsZw=";
    };
  });

  firmware = lib.makeOverridable buildSplitKeyboard {
    src = filteredSrc;
    inherit zephyrDepsHash;
    name = "corne_min";
    board = "corne_min_%PART%";
    shield = "rgbled_adapter";
    enableZmkStudio = true;
    nativeBuildInputs = [ setuptools-compat ];
    passthru = { reset = resetFirmware; };
  };

  resetFirmware = buildKeyboard {
    src = filteredSrc;
    inherit zephyrDepsHash;
    name = "corne_min_settings_reset";
    board = "corne_min_left";
    shield = "settings_reset";
  };

in firmware
