#!/bin/bash

# Deploy EigenShield Hook to Base Sepolia
# Make sure you have Base Sepolia ETH in your deployer wallet

export PRIVATE_KEY=885193e06bfcfbff6348f1b9caf486a18c2b927e66382223d7c1cafa9858bb72
export DEPLOYER_PRIVATE_KEY=885193e06bfcfbff6348f1b9caf486a18c2b927e66382223d7c1cafa9858bb72
export BASE_SEPOLIA_RPC_URL=https://base-sepolia.infura.io/v3/11dfc0d86c9e4451b6e8cc57704dc772

echo "Deploying EigenShield Hook to Base Sepolia..."
echo "Pool Manager: 0x498581fF718922c3f8e6A244956aF099B2652b2b"

forge script script/DeployBaseSepolia.s.sol:DeployBaseSepoliaScript \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast \
  -vvvv

echo "Deployment complete! Check the output above for the deployed contract address."

