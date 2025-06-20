#!/bin/bash

# 确保脚本在错误时退出
set -e

# 获取项目根目录的绝对路径
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 检查参数
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <version> [--skip-deploy] [--skip-release] [--skip-tag]"
    echo "Options:"
    echo "  --skip-deploy   Skip deploying to Maven Central"
    echo "  --skip-release  Skip creating GitHub/GitLab release"
    echo "  --skip-tag      Skip creating and pushing Git tag"
    echo "Examples:"
    echo "  $0 1.0.0                         # Full release"
    echo "  $0 1.0.0 --skip-deploy           # Skip Maven Central deployment"
    echo "  $0 1.0.0 --skip-release          # Skip GitHub/GitLab release"
    echo "  $0 1.0.0 --skip-tag              # Skip Git tag creation"
    echo "  $0 1.0.0 --skip-deploy --skip-release  # Only update version and push"
    exit 1
fi

NEW_VERSION=$1
SKIP_DEPLOY=false
SKIP_RELEASE=false
SKIP_TAG=false

# 解析命令行参数
shift # 移除版本参数
while [ "$#" -gt 0 ]; do
    case "$1" in
        --skip-deploy)
            SKIP_DEPLOY=true
            ;;
        --skip-release)
            SKIP_RELEASE=true
            ;;
        --skip-tag)
            SKIP_TAG=true
            ;;
        *)
            echo "Unknown parameter: $1"
            exit 1
            ;;
    esac
    shift
done

# 验证版本号格式
if ! [[ $NEW_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Version must be in format X.Y.Z"
    exit 1
fi

# 检查必要的命令是否存在
command -v mvn >/dev/null 2>&1 || { echo "Error: mvn is required but not installed" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "Error: git is required but not installed" >&2; exit 1; }
command -v sed >/dev/null 2>&1 || { echo "Error: sed is required but not installed" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "Error: curl is required but not installed" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq is required but not installed" >&2; exit 1; }

# 检测是 GitHub 还是 GitLab
REMOTE_URL=$(git remote get-url origin)
if [[ "$REMOTE_URL" == *"github.com"* ]]; then
    REPO_TYPE="github"
    REPO_HOST="github.com"
    command -v gh >/dev/null 2>&1 || { echo "Error: GitHub CLI (gh) is required but not installed. Install it from https://cli.github.com/" >&2; exit 1; }
else
    REPO_TYPE="gitlab"
    # 检查 GitLab 配置
    if [ -z "$GITLAB_TOKEN" ]; then
        echo "Error: GITLAB_TOKEN environment variable is required for GitLab releases"
        echo "Please set it with: export GITLAB_TOKEN=your_token"
        exit 1
    fi
    if [ -z "$GITLAB_HOST" ]; then
        echo "Error: GITLAB_HOST environment variable is required for self-hosted GitLab"
        echo "Please set it with: export GITLAB_HOST=your.gitlab.host"
        echo "Example: export GITLAB_HOST=gitlab.example.com"
        exit 1
    fi
    REPO_HOST="$GITLAB_HOST"

    # 从远程 URL 中提取项目路径
    if [[ "$REMOTE_URL" =~ ${REPO_HOST}[/:](.*).git$ ]]; then
        GITLAB_PROJECT_PATH="${BASH_REMATCH[1]}"
        # URL encode the project path
        GITLAB_PROJECT_PATH_ENCODED=$(echo "$GITLAB_PROJECT_PATH" | sed 's|/|%2F|g')
    else
        echo "Error: Could not determine GitLab project path from remote URL"
        exit 1
    fi
fi

# 获取当前分支
CURRENT_BRANCH=$(git symbolic-ref --short HEAD)

echo "Project root: ${PROJECT_ROOT}"
echo "Current branch: ${CURRENT_BRANCH}"
echo "New version: ${NEW_VERSION}"
echo "Repository type: ${REPO_TYPE}"
echo "Repository host: ${REPO_HOST}"


# 确保工作目录干净
if [[ -n $(git status -s) ]]; then
    echo "Error: Working directory is not clean"
    git status
    exit 1
fi

# 检查是否有未提交的更改
if [[ -n $(git diff origin/${CURRENT_BRANCH}) ]]; then
    echo "Error: There are unpushed changes"
    git diff origin/${CURRENT_BRANCH} --stat
    exit 1
fi

# 拉取最新代码
echo "Pulling latest changes..."
git pull origin ${CURRENT_BRANCH}

# 检查 CHANGELOG.md 是否存在
if [ ! -f "CHANGELOG.md" ]; then
    echo "Error: CHANGELOG.md not found"
    exit 1
fi

# 检查 pom.xml 是否存在
if [ ! -f "pom.xml" ]; then
    echo "Error: pom.xml not found"
    exit 1
fi

# 获取上一个版本的标签
PREV_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -z "$PREV_VERSION" ]; then
    # 如果没有找到标签，使用第一个提交
    PREV_VERSION=$(git rev-list --max-parents=0 HEAD)
fi

# 生成变更日志条目
echo "Generating changelog entries..."
TEMP_LOG=$(mktemp)
echo -e "\n## [${NEW_VERSION}] - $(date +%Y-%m-%d)\n" > "$TEMP_LOG"

# 获取提交记录并按类型分类
if [ -n "$PREV_VERSION" ]; then
    # Features
    echo -e "\n### ⭐ New Features\n" >> "$TEMP_LOG"
    git log ${PREV_VERSION}..HEAD --pretty=format:"- %s" --reverse | grep -v "^- \[CI Skip\]" | grep -v "^- Merge" | grep -v "^- \[maven-release-plugin\]" | grep "^- feat:" >> "$TEMP_LOG" || true

    # Bug Fixes
    echo -e "\n### 🐛 Bug Fixes\n" >> "$TEMP_LOG"
    git log ${PREV_VERSION}..HEAD --pretty=format:"- %s" --reverse | grep -v "^- \[CI Skip\]" | grep -v "^- Merge" | grep -v "^- \[maven-release-plugin\]" | grep "^- fix:" >> "$TEMP_LOG" || true

    # Documentation
    echo -e "\n### 📚 Documentation\n" >> "$TEMP_LOG"
    git log ${PREV_VERSION}..HEAD --pretty=format:"- %s" --reverse | grep -v "^- \[CI Skip\]" | grep -v "^- Merge" | grep -v "^- \[maven-release-plugin\]" | grep "^- docs:" >> "$TEMP_LOG" || true

    # Chores
    echo -e "\n### 🔧 Chores\n" >> "$TEMP_LOG"
    git log ${PREV_VERSION}..HEAD --pretty=format:"- %s" --reverse | grep -v "^- \[CI Skip\]" | grep -v "^- Merge" | grep -v "^- \[maven-release-plugin\]" | grep "^- chore:" >> "$TEMP_LOG" || true

    # CI
    echo -e "\n### 🔄 CI\n" >> "$TEMP_LOG"
    git log ${PREV_VERSION}..HEAD --pretty=format:"- %s" --reverse | grep -v "^- \[CI Skip\]" | grep -v "^- Merge" | grep -v "^- \[maven-release-plugin\]" | grep "^- ci:" >> "$TEMP_LOG" || true

    # Build
    echo -e "\n### 🏗️ Build\n" >> "$TEMP_LOG"
    git log ${PREV_VERSION}..HEAD --pretty=format:"- %s" --reverse | grep -v "^- \[CI Skip\]" | grep -v "^- Merge" | grep -v "^- \[maven-release-plugin\]" | grep "^- build:" >> "$TEMP_LOG" || true

    # Style
    echo -e "\n### 💄 Style\n" >> "$TEMP_LOG"
    git log ${PREV_VERSION}..HEAD --pretty=format:"- %s" --reverse | grep -v "^- \[CI Skip\]" | grep -v "^- Merge" | grep -v "^- \[maven-release-plugin\]" | grep "^- style:" >> "$TEMP_LOG" || true

    # Refactor
    echo -e "\n### ♻️ Refactor\n" >> "$TEMP_LOG"
    git log ${PREV_VERSION}..HEAD --pretty=format:"- %s" --reverse | grep -v "^- \[CI Skip\]" | grep -v "^- Merge" | grep -v "^- \[maven-release-plugin\]" | grep "^- refactor:" >> "$TEMP_LOG" || true

    # Performance
    echo -e "\n### ⚡ Performance\n" >> "$TEMP_LOG"
    git log ${PREV_VERSION}..HEAD --pretty=format:"- %s" --reverse | grep -v "^- \[CI Skip\]" | grep -v "^- Merge" | grep -v "^- \[maven-release-plugin\]" | grep "^- perf:" >> "$TEMP_LOG" || true

    # Test
    echo -e "\n### ✅ Test\n" >> "$TEMP_LOG"
    git log ${PREV_VERSION}..HEAD --pretty=format:"- %s" --reverse | grep -v "^- \[CI Skip\]" | grep -v "^- Merge" | grep -v "^- \[maven-release-plugin\]" | grep "^- test:" >> "$TEMP_LOG" || true

    # Dependencies
    echo -e "\n### ⬆️ Dependencies\n" >> "$TEMP_LOG"
    git log ${PREV_VERSION}..HEAD --pretty=format:"- %s" --reverse | grep -v "^- \[CI Skip\]" | grep -v "^- Merge" | grep -v "^- \[maven-release-plugin\]" | grep "^- deps:" >> "$TEMP_LOG" || true
fi

# 更新 CHANGELOG.md
echo "Updating CHANGELOG.md..."
# 检查版本是否已存在于 CHANGELOG.md
if grep -q "## \[${NEW_VERSION}\]" "CHANGELOG.md"; then
    echo "Warning: Version ${NEW_VERSION} already exists in CHANGELOG.md, skipping changelog update"
else
    if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' -e '7a\'"$(cat "$TEMP_LOG")"'' "CHANGELOG.md"
else
    # Linux
    sed -i '7a '"$(cat "$TEMP_LOG")" "CHANGELOG.md"
    fi
fi

# 更新版本号
echo "Updating version to ${NEW_VERSION}..."
mvn versions:set -DnewVersion=${NEW_VERSION} -DgenerateBackupPoms=false

# 提交更改
echo "Committing changes..."
git add pom.xml CHANGELOG.md
git commit -m "Release version ${NEW_VERSION}"

# 创建和推送标签
if [ "$SKIP_TAG" = false ]; then
    echo "Creating tag v${NEW_VERSION}..."
    git tag -a "v${NEW_VERSION}" -m "Release version ${NEW_VERSION}"
    echo "Pushing tag..."
    git push origin "v${NEW_VERSION}"
else
    echo "Skipping tag creation and push..."
fi

# 推送更改
echo "Pushing changes..."
git push origin ${CURRENT_BRANCH}

# 生成发布文件
echo "Generating release artifacts..."
if [ "$SKIP_DEPLOY" = false ]; then
    echo "Building and deploying to Maven Central..."
    mvn deploy -Prelease
else
    echo "Building release artifacts without deploying..."
    mvn clean package gpg:sign -Prelease -DskipTests
fi

# 收集要上传的文件
echo "Collecting release artifacts..."
ARTIFACTS_DIR=$(mktemp -d)
find target -name "*.jar" -o -name "*.pom" -o -name "*.asc" -exec cp {} "$ARTIFACTS_DIR" \;

# 创建发布
if [ "$SKIP_RELEASE" = false ]; then
    echo "Creating release..."
    if [ "$REPO_TYPE" = "github" ]; then
        # 创建 GitHub Release
        gh release create "v${NEW_VERSION}" \
            --title "Release v${NEW_VERSION}" \
            --notes-file "$TEMP_LOG" \
            --target "$CURRENT_BRANCH" \
            --verify-tag \
            --generate-notes \
            "$ARTIFACTS_DIR"/*
else
    # 创建 GitLab Release
    # 获取标签的 commit hash
    TAG_SHA=$(git rev-parse "v${NEW_VERSION}")

    # 准备发布说明
    RELEASE_NOTES=$(cat "$TEMP_LOG")

    # 创建 GitLab Release
    curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
         --header "Content-Type: application/json" \
         --data @- \
         "https://${GITLAB_HOST}/api/v4/projects/${GITLAB_PROJECT_PATH_ENCODED}/releases" <<EOF
{
  "name": "Release v${NEW_VERSION}",
  "tag_name": "v${NEW_VERSION}",
  "ref": "${TAG_SHA}",
  "description": "${RELEASE_NOTES}"
}
EOF

    # 上传发布文件
    for file in "$ARTIFACTS_DIR"/*; do
        filename=$(basename "$file")
        echo "Uploading $filename..."
        curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
             --upload-file "$file" \
             "https://${GITLAB_HOST}/api/v4/projects/${GITLAB_PROJECT_PATH_ENCODED}/releases/v${NEW_VERSION}/assets/links" \
             -F "name=${filename}" \
             -F "url=file://${filename}" \
             -F "link_type=package"
    done
    fi
else
    echo "Skipping release creation..."
fi

# 清理临时文件和目录
rm "$TEMP_LOG"
rm -rf "$ARTIFACTS_DIR"

# 更新到下一个开发版本
NEXT_DEV_VERSION="${NEW_VERSION%.*}.$((${NEW_VERSION##*.}+1))-SNAPSHOT"
echo "Updating to next development version ${NEXT_DEV_VERSION}..."
mvn versions:set -DnewVersion=${NEXT_DEV_VERSION} -DgenerateBackupPoms=false

# 提交下一个开发版本
git add .
git commit -m "Prepare for next development iteration ${NEXT_DEV_VERSION}"
git push origin ${CURRENT_BRANCH}

echo "Release ${NEW_VERSION} completed successfully!"
echo "Next development version is ${NEXT_DEV_VERSION}"
