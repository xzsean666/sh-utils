# PM2 管理脚本

这是一个用于管理 NestJS 应用的 PM2 脚本，支持从 `.env` 文件读取配置。

## 功能特性

- 自动检测并安装 PM2 (支持 npm、yarn、pnpm)
- 从 `.env` 文件读取配置参数
- 支持多实例部署 (`-i` 参数)
- 智能端口占用检测
- 应用状态管理和监控
- 详细的错误处理和用户提示

## 使用方法

```bash
# 启动应用
./pm2.sh --start

# 停止应用
./pm2.sh --stop

# 重启应用
./pm2.sh --restart

# 查看应用状态
./pm2.sh --status
```

## 配置选项

在项目根目录的 `.env` 文件中配置以下参数：

### 基本配置

```env
# 应用端口 (默认: 3000)
PORT=3000

# 运行环境 (默认: production)
NODE_ENV=production
```

### PM2 配置

```env
# PM2 实例数量 (默认: 1)
# 可以是数字或 'max' (使用所有 CPU 核心)
PM2_INSTANCES=1

# 最大内存限制 (默认: 4096M)
PM2_MAX_MEMORY=4096M
```

### 日志配置 (可选)

```env
# 合并日志文件路径
PM2_LOG_FILE=logs/app.log

# 错误日志文件路径
PM2_ERROR_FILE=logs/error.log

# 输出日志文件路径
PM2_OUT_FILE=logs/out.log
```

## 与 NestJS 的兼容性

### 环境变量传递

脚本会将以下环境变量传递给 NestJS 应用：

- `NODE_ENV`: 运行环境
- `PORT`: 应用端口

### NestJS 配置示例

在 NestJS 应用中，你可以这样读取环境变量：

```typescript
// main.ts
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // 从环境变量读取端口，与脚本保持一致
  const port = process.env.PORT || 3000;

  await app.listen(port);
  console.log(`Application is running on: http://localhost:${port}`);
}
bootstrap();
```

```typescript
// app.module.ts
import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: '.env', // 确保读取 .env 文件
    }),
  ],
  // ...
})
export class AppModule {}
```

## 脚本工作流程

### 启动流程 (`--start`)

1. 检查并安装 PM2
2. 读取 `.env` 配置
3. 检查端口占用
4. 检查是否已有运行的实例
5. 执行 `npm run build`
6. 验证构建产物
7. 生成唯一应用名称
8. 启动 PM2 进程

### 停止流程 (`--stop`)

1. 读取应用名称
2. 验证进程存在
3. 停止并删除 PM2 进程
4. 清理名称文件

### 重启流程 (`--restart`)

1. 验证应用存在
2. 执行构建
3. 重启 PM2 进程

## 故障排除

### 常见问题

1. **端口被占用**

   ```bash
   # 查看端口占用
   lsof -i:3000

   # 停止现有进程
   ./pm2.sh --stop
   ```

2. **构建失败**

   ```bash
   # 手动构建检查
   npm run build

   # 检查构建产物
   ls -la dist/
   ```

3. **PM2 安装失败**
   ```bash
   # 手动安装
   npm install -g pm2
   # 或
   yarn global add pm2
   # 或
   pnpm install -g pm2
   ```

### 日志查看

```bash
# 查看 PM2 日志
pm2 logs

# 查看特定应用日志
pm2 logs <app-name>

# 实时监控
pm2 monit
```

## 注意事项

1. 确保项目根目录有 `.env` 文件
2. 确保 `npm run build` 命令可用
3. 确保构建后的文件在 `dist/main.js`
4. 脚本会自动管理应用名称，避免手动修改 `app.name` 文件
5. 多实例模式下，PM2 会自动进行负载均衡

## 示例配置文件

参考 `pm2.env.example` 文件获取完整的配置示例。
