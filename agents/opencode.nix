{ mkAgentImage, agents, pkgs }:

mkAgentImage {
  name = "agent-images/opencode";
  agent = agents.opencode;
  entrypoint = [ "opencode" ];
}
