# Turns classification.nix into every artifact that depends on it.
#
# Generating these rather than hand-writing them is the point: the exclude
# rules, the documentation and the test fixture cannot drift from each other,
# because there is only one place to change.
#
# Strings are assembled by explicit concatenation rather than indented Nix
# blocks — interpolating multi-line content into an indented '' block produces
# ragged output, which matters when the result is a markdown table.

{ pkgs, classification }:

let
  inherit (pkgs) lib;

  classNames = lib.attrNames classification;
  globsOf = name: lib.attrNames classification.${name}.paths;

  backedUpClasses = lib.filter (n: classification.${n}.backup) classNames;
  excludedClasses = lib.filter (n: !classification.${n}.backup) classNames;

  # The only list that removes data from a snapshot.
  excludedGlobs = lib.concatMap globsOf excludedClasses;

  # Every glob the coverage check knows about. A live path matching none of
  # these is unclassified, and is reported rather than ignored.
  allGlobs = lib.concatMap globsOf classNames;

  nl = lib.concatStringsSep "\n";
  toFile = xs: nl (xs ++ [ "" ]);

  classSection = name:
    let
      c = classification.${name};
      rows = lib.mapAttrsToList (glob: why: "| `" + glob + "` | " + why + " |") c.paths;
    in
    nl ([
      ("## `" + name + "`")
      ""
      c.summary
      ""
      ("**Included in backups: " + (if c.backup then "yes" else "no") + "**")
      ""
      "| Path | Why |"
      "|---|---|"
    ] ++ rows ++ [ "" ]);

  docsText = nl ([
    "<!-- GENERATED from classification.nix. Do not edit by hand — edit the manifest. -->"
    ""
    "# Path classification"
    ""
    "Every path in the agent state directory belongs to exactly one class below."
    "A path matching no entry is treated as `earned`: it is backed up, and"
    "reported as unclassified. Classification fails toward capture, so an"
    "upstream release that adds a new path produces noise, never silent loss."
    ""
    ("Backed up: " + nl' backedUpClasses + ". Excluded: " + nl' excludedClasses + ".")
    ""
  ] ++ map classSection classNames);

  nl' = xs: lib.concatStringsSep ", " (map (x: "`" + x + "`") xs);

  excludedGlobsFile = pkgs.writeText "excluded-globs.txt" (toFile excludedGlobs);
  classifiedGlobsFile = pkgs.writeText "classified-globs.txt" (toFile allGlobs);
  docsFile = pkgs.writeText "classification.md" docsText;

in
rec {
  inherit excludedGlobs allGlobs excludedGlobsFile classifiedGlobsFile docsFile;
  inherit backedUpClasses excludedClasses;

  # Assembled directory the CLI reads at runtime. Referencing one store path
  # keeps the script from needing to know how many artifacts there are.
  out = pkgs.runCommand "claude-state-classification" { } ''
    mkdir -p "$out"
    cp ${excludedGlobsFile}   "$out/excluded-globs.txt"
    cp ${classifiedGlobsFile} "$out/classified-globs.txt"
    cp ${docsFile}            "$out/classification.md"
  '';
}
