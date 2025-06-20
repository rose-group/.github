# 🚀 快速发布指南

## 📋 发布步骤

### 1️⃣ 准备发布
```bash
# 创建发布分支
git checkout -b release-v1.0.0

# 运行发布脚本
bash release.sh -v 1.0.0 -c
```

### 2️⃣ 创建 PR
- 在 GitHub 创建 Pull Request
- 等待 CI 检查通过 ✅
- 代码审查后合并 🔀

### 3️⃣ 自动发布
- 标签推送自动触发 `maven-release.yml` 🏷️
- 自动构建、签名、发布到 Maven Central 📦
- 自动创建 GitHub Release 🎯
- 自动部署文档到 GitHub Pages 📚

## ⚡ 常用命令

```bash
# 补丁版本升级
bash release.sh -v patch -c

# 预览模式
bash release.sh -v minor -c -n

# 指定具体版本
bash release.sh -v 2.1.0 -c

# 允许脏工作目录
bash release.sh -v patch -c -a
```

## 🔍 检查要点

- [ ] ✅ 所有测试通过
- [ ] 📝 CHANGELOG.md 更新正确  
- [ ] 🔢 版本号格式正确
- [ ] 🏷️ 标签自动推送
- [ ] 🎯 GitHub Release 创建成功

## 🆘 紧急情况

```bash
# 删除错误标签
git tag -d v1.0.0
git push origin :refs/tags/v1.0.0

# 回滚版本
mvn versions:set -DnewVersion=1.0.0-SNAPSHOT
git commit -am "Rollback to SNAPSHOT"
```

---
💡 **提示**: 详细信息请参考 [WORKFLOW_GUIDE.md](WORKFLOW_GUIDE.md) 