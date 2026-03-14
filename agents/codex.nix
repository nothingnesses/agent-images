{ mkAgentImage, agents, pkgs }:

mkAgentImage {
  name = "agent-images/codex";
  agent = agents.codex;
  entrypoint = [ "codex" ];
}
