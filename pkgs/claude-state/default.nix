# The CLI.
#
# writeShellApplication runs shellcheck at build time, so an unlinted script
# cannot be produced — there is no separate lint step to forget to run.
#
# The classification store path is baked in as a prelude rather than looked up
# at runtime: the binary and the rules it enforces are the same artifact, and
# cannot be updated independently of one another.

{ pkgs, classify }:

pkgs.writeShellApplication {
  name = "claude-state";

  runtimeInputs = with pkgs; [
    restic
    jq
    coreutils
    findutils
    diffutils
    gnugrep
  ];

  text = ''
    CLASSIFICATION_DIR="${classify.out}"
  '' + builtins.readFile ./claude-state.sh;
}
