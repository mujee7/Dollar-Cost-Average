require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.20",
  // hardhat.config.ts
  networks: {
    hardhat: {
      forking: {
        url: `https://base-mainnet.g.alchemy.com/v2/YuO0fhrkSK-uPHnvE2rUTATsxKvCdaQq`,
        blockNumber: 14238611,
        enabled: true,
      },
      chains: {
        8453: {
          hardforkHistory: {
            london: 14038611
          }
        }
      }
    },
  }
};
