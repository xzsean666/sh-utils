#!/bin/bash

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查必要工具
check_dependencies() {
    if ! command -v node &> /dev/null; then
        log_error "Node.js 未安装，请先安装 Node.js"
        exit 1
    fi
    
    if ! command -v pnpm &> /dev/null; then
        log_info "正在安装 pnpm..."
        npm install -g pnpm
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq 未安装，请先安装 jq"
        exit 1
    fi
}

check_dependencies

# 创建项目结构
log_info "创建项目结构..."
mkdir -p src
mkdir -p tests

# 初始化项目
log_info "初始化项目..."
pnpm init

# 安装依赖 - 使用 Vitest 替代 Jest (更快、原生支持 ESM 和 TypeScript)
log_info "安装依赖..."
pnpm add typescript @types/node -D
pnpm add vitest -D
pnpm add tsx -D  # 用于开发时直接运行 TS 文件
pnpm add tsup -D

# 创建 tsconfig.json - 现代化 ESM 配置
log_info "创建 tsconfig.json..."
cat > tsconfig.json << 'EOL'
{
  "compilerOptions": {
    "target": "ES2024",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "outDir": "./main",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "experimentalDecorators": true,
    "emitDecoratorMetadata": true,
    "strictNullChecks": true,
    "strictPropertyInitialization": false,
    "noImplicitAny": false,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noUncheckedIndexedAccess": true,
    "noEmitOnError": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "main", "tests", "src/utils/**/*" ,"src/sdks.ts" ]
}
EOL

# 创建 vitest.config.ts - Vitest 配置
log_info "创建 vitest.config.ts..."
cat > vitest.config.ts << 'EOL'
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
    },
  },
});
EOL

log_info "tsup.bundle.config.ts..."
cat > tsup.bundle.config.ts << 'EOL'

import { defineConfig } from 'tsup'

export default defineConfig({
  entry: ['src/index.ts'],
  format: ['esm'],
  dts: true,
  outDir: 'main',
  clean: true,
  noExternal: [/.*/],  // 将所有依赖打包进去
  // 排除 Node.js 内置模块和原生模块
  external: [
    'fs', 'path', 'os', 'crypto', 'stream', 'util', 'events', 'buffer', 
    'url', 'querystring', 'http', 'https', 'net', 'tls', 'child_process',
    'assert', 'zlib', 'readline', 'string_decoder', 'timers', 'dns',
    'module', 'node:module',  // 避免与 banner 中的 createRequire 重复
    'sqlite3',  // 原生模块需要保持外部
  ],
  // 在 ESM 中支持 require 和 __dirname
  banner: {
    js: `import { createRequire } from 'module';import { fileURLToPath } from 'url';import { dirname } from 'path';const require = createRequire(import.meta.url);const __filename = fileURLToPath(import.meta.url);const __dirname = dirname(__filename);`,
  },
})
EOL

# 创建示例 index.ts 文件
log_info "创建示例源文件..."
cat > src/index.ts << 'EOL'
export function sum(a: number, b: number): number {
  return a + b;
}

export function multiply(a: number, b: number): number {
  return a * b;
}

// 主入口
async function main() {
  console.log('Hello, TypeScript with ESM!');
  console.log(`1 + 2 = ${sum(1, 2)}`);
}

main().catch(console.error);
EOL

log_info "创建sdks源文件..."
cat > src/sdks.ts << 'EOL'
export * from '../utils/dbUtils/KVSqljs';
export * from '../utils/dbUtils/KVCache';
export * from '../utils/dbUtils/KVSqljsCache';
EOL

# 创建示例测试文件
log_info "创建示例测试文件..."
cat > tests/index.test.ts << 'EOL'
import { describe, it, expect } from 'vitest';
import { sum, multiply } from '../src/index.js';

describe('sum function', () => {
  it('should add two numbers correctly', () => {
    expect(sum(1, 2)).toBe(3);
  });

  it('should handle negative numbers', () => {
    expect(sum(-1, 1)).toBe(0);
  });
});

describe('multiply function', () => {
  it('should multiply two numbers correctly', () => {
    expect(multiply(2, 3)).toBe(6);
  });
});
EOL

# 更新 package.json 中的脚本和配置
log_info "更新 package.json..."
jq '. + {
  "type": "module",
  "main": "main/index.js",
  "types": "main/index.d.ts",
  "exports": {
    ".": {
      "types": "./main/index.d.ts",
      "import": "./main/index.js"
    }
  },
  "scripts": {
    "clean": "rm -rf main",
    "build:helpers": "tsx src/utils/scripts/copyDependencies.ts --input src/sdks.ts --output src/helpers",
    "build": "pnpm clean && tsup src/index.ts --format esm --dts --outDir main --clean",
    "build:bundle": "pnpm clean && tsup --config tsup.bundle.config.ts",
    "start": "node main/index.js",
    "dev": "tsx watch src/index.ts",
    "dev:build": "tsc --watch",
    "test": "vitest run",
    "test:watch": "vitest",
    "test:coverage": "vitest run --coverage",
    "typecheck": "tsc --noEmit",
    "lint": "tsc --noEmit",
    "prepublishOnly": "pnpm build"
  },
  "files": ["main"],
  "engines": {
    "node": ">=20.0.0"
  },
  "packageManager": "pnpm@10.24.0"
}' package.json > temp.json && mv temp.json package.json

# 创建 .gitignore
log_info "创建 .gitignore..."
cat > .gitignore << 'EOL'
# Dependencies
node_modules/

# Build output
main/

# Test coverage
coverage/

# IDE
.idea/
.vscode/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Environment
.env
.env.local
.env.*.local

# Logs
logs/
*.log
npm-debug.log*
pnpm-debug.log*

# Project specific
# src/utils
db/

# Temp files
*.tmp
*.temp
EOL

# 创建 .npmrc - pnpm 配置
log_info "创建 .npmrc..."
cat > .npmrc << 'EOL'
shamefully-hoist=true
strict-peer-dependencies=false
auto-install-peers=true
EOL

# 创建 utils 软链接 (如果目标存在)
if [ -d "/home/sean/git/node-utils/src" ]; then
    log_info "创建 utils 软链接..."
    ln -sf /home/sean/git/node-utils/src src/utils
else
    log_warn "utils 目录不存在，跳过创建软链接"
fi

# 创建 README.md
log_info "创建 README.md..."
cat > README.md << 'EOL'
# TypeScript 项目模板

现代化的 TypeScript 项目模板，使用 ESM 模块系统和 Vitest 测试框架。

## 特性

- 🚀 **ES Modules** - 使用原生 ESM 模块系统
- 📦 **TypeScript** - 最新的 TypeScript 特性
- ⚡ **Vitest** - 快速的单元测试框架
- 🔥 **tsx** - 开发时直接运行 TypeScript
- 📝 **类型声明** - 自动生成 .d.ts 文件

## 可用的命令

| 命令 | 说明 |
|------|------|
| `pnpm build` | 构建项目 |
| `pnpm start` | 运行编译后的项目 |
| `pnpm dev` | 开发模式（使用 tsx 直接运行） |
| `pnpm dev:build` | 开发模式（监听并编译） |
| `pnpm test` | 运行测试 |
| `pnpm test:watch` | 监听模式运行测试 |
| `pnpm test:coverage` | 运行测试并生成覆盖率报告 |
| `pnpm typecheck` | 类型检查 |

## 项目结构

```
.
├── src/              # 源代码目录
│   └── index.ts      # 主入口文件
├── tests/            # 测试文件目录
│   └── index.test.ts # 测试文件
├── main/             # 编译输出目录
├── vitest.config.ts  # Vitest 配置文件
├── tsconfig.json     # TypeScript 配置文件
└── package.json      # 项目配置文件
```

## 环境要求

- Node.js >= 20.0.0
- pnpm >= 10.0.0
EOL

log_info "=========================================="
log_info "TypeScript 项目（ESM + Vitest）初始化完成！"
log_info "=========================================="
echo ""
echo "您可以使用以下命令："
echo "  pnpm dev          - 开发模式（热重载）"
echo "  pnpm build        - 构建项目"
echo "  pnpm start        - 运行项目"
echo "  pnpm test         - 运行测试"
echo "  pnpm test:watch   - 监听模式运行测试"
echo "  pnpm test:coverage - 测试覆盖率"
echo ""
log_info "开始开发: pnpm dev" 