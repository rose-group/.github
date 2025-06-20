#!/bin/bash -e
##https://blogs.sap.com/2018/06/22/generating-release-notes-from-git-commit-messages-using-basic-shell-commands-gitgrep/

# 获取上一个版本的标签
PREV_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -z "$PREV_VERSION" ]; then
    # 如果没有找到标签，使用第一个提交
    PREV_VERSION=$(git rev-list --max-parents=0 HEAD)
fi

echo "Generating changelog entries..."
git --no-pager log ${PREV_VERSION}..HEAD --pretty=format:"- %s" --reverse | grep -v "^- \[CI Skip\]" | grep -v "^- Merge" | grep -v "^- \[maven-release-plugin\]"
