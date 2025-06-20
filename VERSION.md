# 版本管理指南

## 目录

- [版本规范](#版本规范)
  - [版本号格式](#版本号格式)
  - [版本号示例](#版本号示例)
- [提交消息规范](#提交消息规范)
  - [提交类型](#提交类型)
  - [提交示例](#提交示例)
- [发布流程](#发布流程)
  - [环境变量配置](#环境变量配置)
  - [发布命令](#发布命令)
  - [可选参数](#可选参数)
  - [自动化流程](#自动化流程)
- [变更日志](#变更日志)
  - [变更类型](#变更类型)
  - [自动生成](#自动生成)
- [最佳实践](#最佳实践)
  - [版本管理](#版本管理)
  - [提交规范](#提交规范)
  - [发布流程](#发布流程-1)
  - [CI/CD](#cicd)
- [故障排除](#故障排除)

## 版本规范

### 版本号格式

本项目使用 [Semantic Versioning](https://semver.org/lang/zh-CN/) 进行版本管理。

版本号格式：`主版本号.次版本号.修订号`（MAJOR.MINOR.PATCH）
- 主版本号：做了不兼容的 API 修改
- 次版本号：做了向下兼容的功能性新增
- 修订号：做了向下兼容的问题修正

### 版本号示例

- 开发版本：1.0.0-SNAPSHOT
- 发布版本：1.0.0
- 预发布版本：1.0.0-RC1
- 测试版本：1.0.0-BETA1
- 内部版本：1.0.0-ALPHA1

## 提交消息规范

项目使用 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/) 规范。

### 提交类型

|     类型     |  说明   |           示例            |
|------------|-------|-------------------------|
| `feat`     | 新功能   | feat: 添加用户认证功能          |
| `fix`      | 修复问题  | fix: 修复登录验证失败问题         |
| `docs`     | 文档更新  | docs: 更新 API 文档         |
| `style`    | 代码格式  | style: 格式化代码            |
| `refactor` | 代码重构  | refactor: 重构认证模块        |
| `perf`     | 性能优化  | perf: 优化查询性能            |
| `test`     | 测试相关  | test: 添加单元测试            |
| `chore`    | 构建/工具 | chore: 更新依赖版本           |
| `ci`       | CI/CD | ci: 添加自动部署配置            |
| `build`    | 构建系统  | build: 修改 Maven 配置      |
| `deps`     | 依赖更新  | deps: 升级 Spring Boot 版本 |

### 提交示例

```bash
feat: 添加用户认证功能

添加基于 JWT 的用户认证功能，包括：
- 用户登录接口
- Token 生成和验证
- 权限控制

Closes #123
```

## 发布流程

### 环境变量配置

#### GitHub

```bash
export GH_TOKEN=your_github_token
```

#### GitLab

```bash
export GITLAB_TOKEN=your_gitlab_token
export GITLAB_HOST=your.gitlab.host  # 如果使用自托管 GitLab
```

### 发布命令

基本用法：

```bash
./release.sh <version>
```

### 可选参数

|        参数        |             说明             |
|------------------|----------------------------|
| `--skip-deploy`  | 跳过发布到 Maven 中央仓库           |
| `--skip-release` | 跳过创建 GitHub/GitLab Release |
| `--skip-tag`     | 跳过创建和推送 Git 标签             |

### 自动化流程

1. 版本检查
   - 验证版本号格式
   - 检查版本冲突
   - 验证 SNAPSHOT 依赖
2. 测试验证
   - 运行单元测试
   - 运行集成测试
   - 检查测试覆盖率
3. 代码质量
   - 运行代码分析
   - 检查代码风格
   - 验证提交消息
4. 构建部署
   - 编译代码
   - 生成文档
   - 打包构件
   - 签名文件
   - 部署到仓库
5. 发布完成
   - 创建标签
   - 生成变更日志
   - 创建 Release
   - 发布通知

## 变更日志

### 变更类型

|      类别       |  说明  | 图标  |
|---------------|------|-----|
| New Features  | 新功能  | ⭐   |
| Bug Fixes     | 问题修复 | 🐛  |
| Documentation | 文档更新 | 📚  |
| Chores        | 其他更改 | 🔧  |
| CI            | 持续集成 | 🔄  |
| Build         | 构建相关 | 🏗️ |
| Style         | 样式调整 | 💄  |
| Refactor      | 代码重构 | ♻️  |
| Performance   | 性能优化 | ⚡   |
| Test          | 测试相关 | ✅   |
| Dependencies  | 依赖更新 | ⬆️  |

### 自动生成

变更日志基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/) 格式，自动从 Git 提交记录中提取。

## 最佳实践

### 版本管理

- 开发分支使用 SNAPSHOT 版本
- 发布分支使用正式版本号
- 预发布使用 RC 后缀
- 每次发布都创建标签

### 提交规范

- 使用规范的提交消息格式
- 提供清晰的变更描述
- 关联相关的 Issue
- 保持提交粒度合适

### 发布流程

- 确保测试全部通过
- 更新文档和变更日志
- 验证构建产物
- 执行完整的测试套件

### CI/CD

- 提交时自动运行测试
- 定期运行安全扫描
- 自动化版本验证
- 自动化变更日志生成
- 自动化发布流程

## 故障排除

### 常见问题

1. 版本已存在

   ```bash
   # 检查版本
   mvn versions:display-dependency-updates
   # 更新版本
   mvn versions:set -DnewVersion=1.0.1-SNAPSHOT
   ```
2. 构建失败

   ```bash
   # 清理缓存
   mvn clean
   # 验证依赖
   mvn dependency:tree
   ```
3. 发布失败

   ```bash
   # 检查配置
   mvn help:effective-settings
   # 验证认证
   mvn help:effective-pom
   ```

### 帮助资源

- [Maven Release Plugin](https://maven.apache.org/maven-release/maven-release-plugin/)
- [Semantic Versioning](https://semver.org/)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [Keep a Changelog](https://keepachangelog.com/)

