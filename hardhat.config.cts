import '@nomicfoundation/hardhat-toolbox';
import type { HardhatUserConfig } from 'hardhat/config';

const config: HardhatUserConfig = {
  typechain: {
    alwaysGenerateOverloads: false,
    tsNocheck: true,
  },
  networks: {
    hardhat: {
      chainId: Number(process.env.HARDHAT_CHAIN_ID ?? 31_337), // https://github.com/NomicFoundation/hardhat/issues/2305
      accounts: { count: 10 }, // Default value is 20, decreasing makes tests start faster.
    },
  },
  paths: {
    tests: './test/contracts',
  },
  solidity: {
    compilers: [
      {
        version: '0.8.12',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: '0.8.27',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
};

export default config;
