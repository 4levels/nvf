inputs: {
  configuration,
  pkgs,
  lib ? pkgs.lib,
  check ? true,
  extraSpecialArgs ? {},
}: let
  inherit (builtins) map filter isString toString getAttr;
  inherit (pkgs) wrapNeovimUnstable vimPlugins;
  inherit (pkgs.vimUtils) buildVimPlugin;
  inherit (pkgs.neovimUtils) makeNeovimConfig;
  inherit (lib.attrsets) recursiveUpdate;
  inherit (lib.asserts) assertMsg;

  extendedLib = import ../lib/stdlib-extended.nix lib inputs;

  nvimModules = import ./modules.nix {
    inherit check pkgs;
    lib = extendedLib;
  };

  module = extendedLib.evalModules {
    modules = [configuration] ++ nvimModules;
    specialArgs = recursiveUpdate {modulesPath = toString ./.;} extraSpecialArgs;
  };

  vimOptions = module.config.vim;

  extraLuaPackages = ps: map (x: ps.${x}) vimOptions.luaPackages;

  buildPlug = {pname, ...} @ args:
    assert assertMsg (pname != "nvim-treesitter") "Use buildTreesitterPlug for building nvim-treesitter.";
      buildVimPlugin (args
        // {
          version = "master";
          src = getAttr ("plugin-" + pname) inputs;
        });

  buildTreesitterPlug = grammars: vimPlugins.nvim-treesitter.withPlugins (_: grammars);

  buildConfigPlugins = plugins:
    map
    (plug: (
      if (isString plug)
      then
        (
          if (plug == "nvim-treesitter")
          then (buildTreesitterPlug vimOptions.treesitter.grammars)
          else if (plug == "flutter-tools-patched")
          then
            (buildPlug {
              pname = "flutter-tools";
              patches = [../patches/flutter-tools.patch];
            })
          else (buildPlug {pname = plug;})
        )
      else plug
    ))
    (filter
      (f: f != null)
      plugins);

  plugins =
    (buildConfigPlugins vimOptions.startPlugins)
    ++ (map (package: {
        plugin = package;
        optional = false;
      })
      (buildConfigPlugins
        vimOptions.optPlugins));

  neovim = wrapNeovimUnstable vimOptions.package (makeNeovimConfig {
    inherit (vimOptions) viAlias;
    inherit (vimOptions) vimAlias;
    inherit extraLuaPackages;
    inherit plugins;
    customRC = vimOptions.builtConfigRC;
  });
in {
  inherit (module) options config;
  inherit (module._module.args) pkgs;
  inherit neovim;
}
