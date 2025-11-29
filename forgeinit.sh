#!/bin/bash

# Install forge-std
forge install --no-commit foundry-rs/forge-std

# Create foundry.toml
cat > foundry.toml << 'EOL'
[profile.default]
src = "contracts"
out = "out"
libs = ["node_modules", "lib"]
remappings = [
    "@openzeppelin/=node_modules/@openzeppelin/",
    "@chainlink/=node_modules/@chainlink/",
    "forge-std/=lib/forge-std/src/"
]
rpc_endpoints = {anvil = "http://localhost:8545",soneium="https://soneium.rpc.scs.startale.com?apikey=CBKpDfekGVM2CdVP8o1hCzjuDHgexAmR",shibuya ="https://rpc.startale.com/shibuya?apikey=j0Hb3fH0xG5E4Xtm5ZgZd7Czda2nIjxh",mainnet = "https://rpc.ankr.com/eth",bnbtest="https://bsc-testnet.public.blastapi.io" ,sepolia ="https://eth-sepolia.api.onfinality.io/public",opbnbtest = "https://opbnb-testnet.nodereal.io/v1/64a9df0874fb4a93b9d0a3849de012d3",optest = "https://optimism-sepolia.public.blastapi.io", lineagoerli = "https://rpc.goerli.linea.build",zkyoto = "https://rpc.startale.com/zkyoto" }
via_ir = true
ignored-error-codes = [
    1878,
    3420,
    2018,
    2066
]
EOL

# Create remappings.txt
cat > remappings.txt << 'EOL'
@openzeppelin/=node_modules/@openzeppelin/
@chainlink/=node_modules/@chainlink/
forge-std/=lib/forge-std/src/
EOL

# Add lib/ to .gitignore
echo "lib/" >> .gitignore

echo "Forge initialization completed!"
