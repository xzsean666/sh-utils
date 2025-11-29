#!/bin/bash

# Create symbolic link from node-utils src/utils to src/utils
ln -s /home/sean/git/node-utils/src/utils src/utils

# Create src/sdk directory if it doesn't exist
mkdir -p src/sdk

# Create src/sdk/index.ts
cat > src/sdk/index.ts << 'EOF'
// SDK entry point
export * from '../utils/dbUtils/KVSqlite';
export * from '../utils/dbUtils/KVCache';
EOF

# Run copyDependencies script
npx ts-node src/utils/scripts/copyDependencies.ts --input src/sdk/index.ts --output src/helpers

# Add build:sdk script to current directory's package.json
if [ -f "package.json" ]; then
    # Check if jq is available
    if command -v jq &> /dev/null; then
        # Use jq to add the build:sdk script
        jq '.scripts["build:sdk"] = "ln -s /home/sean/git/node-utils/src/utils src/utils && mkdir -p src/sdk && npx ts-node src/utils/scripts/copyDependencies.ts --input src/sdk/index.ts --output src/helpers"' package.json > package.json.tmp && mv package.json.tmp package.json
        echo "Added build:sdk script to package.json"
    else
        echo "jq not found. Please manually add the following to your package.json scripts section:"
        echo '"build:sdk": "ln -s /home/sean/git/node-utils/src/utils src/utils && mkdir -p src/sdk && npx ts-node src/utils/scripts/copyDependencies.ts --input src/sdk/index.ts --output src/helpers"'
    fi
else
    echo "No package.json found in current directory"
fi

echo "Setup completed!"