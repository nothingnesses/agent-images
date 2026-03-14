{ mkAgentImage, agents, pkgs }:

mkAgentImage {
  name = "agent-images/gemini";
  agent = agents.gemini-cli;
  entrypoint = [ "gemini" ];
}
