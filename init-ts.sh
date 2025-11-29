#!/bin/bash

# 创建项目结构
mkdir -p src
mkdir -p tests
npm install -g pnpm

# 初始化项目
pnpm init

# 安装依赖
pnpm add typescript jest @types/node @types/jest ts-jest -D

# 创建 tsconfig.json
cat > tsconfig.json << EOL
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "CommonJS",
    "moduleResolution": "node",
    "outDir": "./dist",
    "rootDir": "./",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "experimentalDecorators": true,
    "emitDecoratorMetadata": true,
    "strictNullChecks": true,
    "strictPropertyInitialization": false,
    "noImplicitAny": false,
    "declaration": true
  },
  "include": ["src/**/*", "tests/**/*"],
  "exclude": ["node_modules"]
}

EOL

# 创建 jest.config.js
cat > jest.config.js << EOL
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  moduleFileExtensions: ['ts', 'tsx', 'js', 'jsx', 'json', 'node']
};
EOL

# 创建示例 index.ts 文件
cat > src/index.ts << EOL
export function sum(a: number, b: number): number {
  return a + b;
}
EOL

# 创建示例测试文件
cat > tests/index.test.ts << EOL
import { sum } from '../src/index';

describe('sum function', () => {
  it('should add two numbers correctly', () => {
    expect(sum(1, 2)).toBe(3);
  });
});
EOL

# 更新 package.json 中的脚本和配置
jq '. + {
  "scripts": {
    "clean": "rm -rf dist",
    "clean-win": "if exist dist rmdir /s /q dist",
    "build": "pnpm clean && tsc",
    "build:deps": "npx ts-node src/utils/scripts/copyDependencies.ts --input src/index.ts --output src/main",
    "build:main": "pnpm clean && pnpm build:deps && tsc -p tsconfig-main.json",
    "start": "pnpm clean && tsc && node dist/index.js",
    "dev": "tsc --watch",
    "test": "jest",
    "test:watch": "jest --watch"
  },
  "type": "commonjs",
  "types": "dist/src/index.d.ts",
  "files": ["dist"],
  "publishConfig": {
    "directory": "dist"
  }
}' package.json > temp.json && mv temp.json package.json

# 创建 .gitignore
cat > .gitignore << EOL
node_modules
dist
coverage
.DS_Store
.env
src/utils
db
EOL

# 创建 utils 软链接
ln -s /home/sean/git/node-utils/src/utils src/utils
cp -r /home/sean/git/node-utils/src/utils/compile/tsconfig-main.json tsconfig-main.json

# 创建 README.md
cat > README.md << EOL
# TypeScript 项目模板

这是一个基础的 TypeScript 项目模板，包含了 Jest 测试框架的配置。

## 可用的命令

- \`pnpm build\`: 构建项目
- \`pnpm start\`: 运行项目
- \`pnpm dev\`: 开发模式（监听文件变化）
- \`pnpm test\`: 运行测试
- \`pnpm test:watch\`: 监听模式运行测试

## 项目结构

\`\`\`
.
├── src/            # 源代码目录
├── tests/          # 测试文件目录
├── dist/           # 编译输出目录
├── jest.config.js  # Jest 配置文件
├── tsconfig.json   # TypeScript 配置文件
└── package.json    # 项目配置文件
\`\`\`
EOL

# 使脚本可执行
chmod +x init-ts-with-jest.sh

echo "TypeScript 项目（带 Jest）初始化完成！"
echo "您可以使用以下命令："
echo "- pnpm build: 构建项目"
echo "- pnpm start: 运行项目"
echo "- pnpm dev: 开发模式"
echo "- pnpm test: 运行测试"
echo "- pnpm test:watch: 监听模式运行测试" 