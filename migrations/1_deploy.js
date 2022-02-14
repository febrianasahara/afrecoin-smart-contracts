const Token = artifacts.require("TokenV2"); // Change to be the artifact contract you'd wish to use

module.exports = (deployer, network, accounts) => {
  deployer.deploy(Token);
};
