# 🚀 Maven 项目自动化发布流程指南

本项目采用完整的自动化 CI/CD 流程，通过 GitHub Actions 和自定义脚本实现从开发到发布的全流程自动化。

## 📋 工作流程概览

### 🔄 持续集成 (CI)
- **触发条件**: Pull Request 到 main/master 分支
- **执行内容**: 快速检查 + 有限范围的完整构建测试
- **目标**: 快速反馈，确保代码质量

### 🚀 持续部署 (CD)  
- **触发条件**: Push 到 main/master 分支
- **执行内容**: 完整构建测试 + 安全扫描 + 快照部署
- **目标**: 全面验证，部署开发版本

### 🎯 正式发布
- **触发条件**: 推送版本标签 (v*.*.*)
- **执行内容**: 生产构建 + 签名 + 发布 + 文档部署
- **目标**: 发布正式版本

## 🛠️ 使用 release.sh 脚本发布

### 基本用法

```bash
# 1. 切换到功能分支
git checkout -b release-1.0.0

# 2. 使用脚本准备发布
bash release.sh -v 1.0.0 -c

# 3. 检查生成的更改
git log --oneline -n 3
cat CHANGELOG.md

# 4. 创建 Pull Request (手动)
# 在 GitHub 网页界面创建 PR

# 5. 合并 PR 后，标签会自动触发正式发布
```

### 高级用法

```bash
# 自动计算补丁版本
bash release.sh -v patch -c

# 预览模式（不做实际更改）
bash release.sh -v minor -c -n

# 允许脏工作目录
bash release.sh -v 1.2.3 -c -a
```

## 📊 GitHub Actions 工作流详解

### 1. CI/CD Pipeline (`ci.yml`)

```yaml
触发条件:
- push: [main, master]
- pull_request: [main, master]
- workflow_dispatch (手动触发)
```

**作业流程:**

#### 🔍 Quick Check (仅 PR)
- 平台: Ubuntu
- Java: 17
- 执行: 编译 + 单元测试 + 基础质量检查
- 时限: 45 分钟

#### 🔄 Full Build & Test
- 平台: 
  - PR: Ubuntu
  - Push: Ubuntu + Windows + macOS
- Java 版本:
  - PR: 17
  - Push: 8, 17, 21
- 执行: 完整构建 + 多平台测试 + 质量分析

#### 🔒 Security Scan (仅主分支)
- OWASP 依赖检查
- 安全报告上传

#### 📦 Deploy Snapshot (仅主分支)
- 条件: 提交信息包含 "SNAPSHOT"
- 部署到快照仓库

#### 📊 Notify Status
- 生成构建摘要报告

### 2. Maven Release (`maven-release.yml`)

```yaml
触发条件:
- push: tags: ["v*"]
```

**发布流程:**
1. 📦 使用 JDK 8 构建和测试
2. 🔐 GPG 签名
3. 📤 部署到 Maven Central
4. 📋 自动生成 Changelog
5. 🎯 创建 GitHub Release
6. 📚 部署文档到 GitHub Pages

### 3. Maven Build (`maven-build.yml`)

可重用的构建工作流，被其他工作流调用:
- 支持多平台矩阵构建
- 支持多 Java 版本测试
- 集成代码质量检查
- SonarCloud 分析

## 🔐 必需的 Secrets 配置

在 GitHub 仓库设置中配置以下 Secrets:

```
MAVEN_USERNAME          # Maven Central 用户名
MAVEN_PASSWORD          # Maven Central 密码
GPG_PRIVATE_KEY         # GPG 私钥
GPG_PASSPHRASE         # GPG 密码短语
SONAR_TOKEN            # SonarCloud Token
```

## 📋 发布检查清单

### 发布前准备
- [ ] 确保所有功能已完成开发
- [ ] 更新版本号相关文档
- [ ] 检查依赖版本是否需要更新
- [ ] 运行完整的本地测试

### 使用 release.sh
- [ ] 创建发布分支
- [ ] 运行 `release.sh` 脚本
- [ ] 检查生成的 CHANGELOG.md
- [ ] 检查版本号更新是否正确
- [ ] 验证脚本输出无错误

### GitHub 操作
- [ ] 创建 Pull Request
- [ ] 等待 CI 检查通过
- [ ] 代码审查
- [ ] 合并 PR
- [ ] 确认标签已推送
- [ ] 验证 Release 自动创建

### 发布后验证
- [ ] 检查 GitHub Release 页面
- [ ] 验证 Maven Central 上的版本
- [ ] 测试文档站点更新
- [ ] 通知相关团队

## ⚡ 性能优化策略

### 🚄 快速反馈
- PR 使用轻量级快速检查
- 并发作业执行
- 智能缓存策略

### 🎯 资源优化
- 按需执行作业
- 条件化的安全检查
- 路径过滤忽略文档更改

### 📊 监控和报告
- 构建状态摘要
- 失败通知
- 性能指标收集

## 🆘 故障排除

### 常见问题

#### release.sh 脚本失败
```bash
# 检查分支状态
git status

# 检查 Maven 配置
mvn help:effective-settings

# 使用 dry-run 模式调试
bash release.sh -v patch -c -n
```

#### GitHub Actions 失败
- 检查 Secrets 配置
- 查看作业日志
- 验证权限设置

#### Maven 部署失败
- 检查 GPG 密钥配置
- 验证 Maven Central 凭据
- 确认版本号格式正确

### 回滚策略

如果发布出现问题：

1. **删除错误的标签**
```bash
git tag -d v1.0.0
git push origin :refs/tags/v1.0.0
```

2. **撤销 GitHub Release**
- 在 GitHub 界面删除 Release
- 或使用 GitHub CLI: `gh release delete v1.0.0`

3. **回滚版本**
```bash
mvn versions:set -DnewVersion=1.0.0-SNAPSHOT
git commit -am "Rollback to SNAPSHOT"
```

## 📞 支持和反馈

如有问题或建议，请：
- 创建 GitHub Issue
- 联系项目维护者
- 查看项目文档和示例 