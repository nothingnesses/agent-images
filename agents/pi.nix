{ mkAgentImage, agents, pkgs }:

mkAgentImage {
  name = "agent-images/pi";
  agent = agents.pi;
  entrypoint = [ "pi" ];
}
