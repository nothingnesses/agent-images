{ mkAgentImage, agents, pkgs }:

mkAgentImage {
  name = "agent-images/claude-code";
  agent = agents.claude-code;
  entrypoint = [ "claude" ];
  extraPackages = with pkgs; [ nodejs ];
}
