#!/bin/bash

# Deploy EigenShield Hook to Base Sepolia
# Make sure you have Base Sepolia ETH in your deployer wallet

# Load environment variables from .env file
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "Error: .env file not found. Please create one from .env.example"
    exit 1
fi

echo "Deploying EigenShield Hook to Base Sepolia..."
echo "Pool Manager: ${BASE_SEPOLIA_POOL_MANAGER:-0x498581fF718922c3f8e6A244956aF099B2652b2b}"

forge script script/DeployBaseSepolia.s.sol:DeployBaseSepoliaScript \
  --rpc-url ${BASE_SEPOLIA_RPC_URL} \
  --broadcast \
  -vvvv

echo "Deployment complete! Check the output above for the deployed contract address."

