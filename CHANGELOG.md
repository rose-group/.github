# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- 🔄 **CI/CD 工作流优化**: 将 `maven-build.yml` 合并到 `ci.yml` 中
  - 保留所有多平台、多JDK版本测试功能
  - 智能矩阵策略：PR 使用快速测试，Push 使用完整测试
  - 支持手动触发时自定义测试矩阵
  - 增强的构建摘要和故障排除信息
- 📊 **改进的质量分析**: 独立的质量检查作业，包含更全面的分析报告
- 🎯 **优化的资源使用**: 根据触发条件智能调整测试范围

### Removed  
- 🗑️ 删除独立的 `maven-build.yml` 文件（功能已合并到 `ci.yml`）

## [0.0.17] - 2025-06-20

### 🧹 Chores

* chore: release version 0.0.16 (714948c)
* chore: release version 0.0.15 (f2b4c22)


## [0.0.16] - 2025-06-20

### 🔨 Code Refactoring

* refactor: 移除旧的发布脚本并优化CHANGELOG生成逻辑以提高可维护性和详细程度 (eb5eed8)
* refactor: 移除旧的发布脚本并优化CHANGELOG生成逻辑以提高可维护性和详细程度 (816c2e0)
* refactor: 删除旧版本文档并优化发布流程相关文件 (768d38d)
* refactor: 删除旧版本文档并优化发布流程相关文件 (9c012f9)
* refactor: 删除旧的发布脚本并重构release.sh以增强功能和可维护性 (b9df2c1)
* refactor: 删除旧的发布脚本并重构release.sh以增强功能和可维护性 (224ce10)
* refactor: 优化脚本以生成更详细的变更日志 (15842d6)

## [0.0.15] - 2025-06-20

### 🔨 Code Refactoring

* refactor: 移除旧的发布脚本并优化CHANGELOG生成逻辑以提高可维护性和详细程度 (816c2e0)
* refactor: 删除旧版本文档并优化发布流程相关文件 (768d38d)
* refactor: 删除旧版本文档并优化发布流程相关文件 (9c012f9)
* refactor: 删除旧的发布脚本并重构release.sh以增强功能和可维护性 (b9df2c1)
* refactor: 删除旧的发布脚本并重构release.sh以增强功能和可维护性 (224ce10)
* refactor: 优化脚本以生成更详细的变更日志 (15842d6)
