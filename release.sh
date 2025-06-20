#!/bin/bash

# A script to automate the release process of a maven project.
# It handles version updates, changelog generation, git tagging, and maven deployment.

# 确保脚本在错误时退出
set -e

# --- Bash check ---
# This script uses features specific to the Bash shell, like '[[...]]' and arrays.
# It will not run correctly with other shells, like 'sh' or 'dash'.
# This check ensures we're running with Bash and provides a helpful error if not.
if [ -z "$BASH_VERSION" ]; then
    printf "Error: This script must be run with Bash, not sh.\n" >&2
    printf "To run it, please use: 'bash %s' or make it executable and run './%s'\n" "$0" "$0" >&2
    exit 1
fi

# -- Cleanup on Exit --
cleanup() {
    if [ -n "$TEMP_LOG" ] && [ -f "$TEMP_LOG" ]; then
        printf "${COLOR_BLUE}Cleaning up temporary files...${COLOR_RESET}\n"
        rm -f "$TEMP_LOG"
    fi
}
trap cleanup EXIT

# --- Color Definitions ---
COLOR_GREEN='\033[0;32m'
COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_BOLD='\033[1m'
COLOR_CYAN='\033[0;36m'
COLOR_YELLOW_BG='\033[43m'
COLOR_BLACK='\033[30m'

# -- Configuration --
# Define the mapping from commit type to changelog section header.
# These arrays must have the same number of elements.
C_TYPE_KEYS=("feat" "fix" "docs" "style" "refactor" "perf" "test" "build" "ci" "chore" "revert")
C_TYPE_VALUES=("✨ Features" "🐛 Bug Fixes" "📝 Documentation" "🎨 Code Style" "🔨 Code Refactoring" "⚡️ Performance Improvements" "✅ Tests" "📦 Build System" "🤖 Continuous Integration" "🧹 Chores" "⏪ Reverts")

# Branch configuration
RELEASE_BRANCH="feature/4.2.11-master"

# -- Global Variables --
NEW_VERSION=""
NEXT_SNAPSHOT_VERSION=""
VERSION_MODE=""
PERFORM_DEPLOY=false
PERFORM_RELEASE=false
PERFORM_TAG=false
PERFORM_CENTRAL_DEPLOY=false
PERFORM_GHPAGES_DEPLOY=false
PERFORM_CHANGELOG=false
DRY_RUN=false
ALLOW_DIRTY=false
REPO_TYPE=""
REPO_HOST=""
GITLAB_PROJECT_PATH_ENCODED=""
CURRENT_BRANCH=""
CURRENT_VERSION=""
CHANGELOG_MODE=""
SPECIFIC_VERSION=""
PROJECT_ROOT=""

# 执行命令或在试运行模式下打印命令
execute() {
    local cmd="$1"

    if [ "$DRY_RUN" = true ]; then
        printf "${COLOR_YELLOW}[DRY RUN] ==> ${COLOR_BOLD}%s${COLOR_RESET}\n" "$cmd"
        return
    fi
    
    # Temporarily disable 'exit on error' to handle errors manually
    set +e
    eval "$cmd"
    local exit_code=$?
    set -e

    if [ $exit_code -ne 0 ]; then
        printf "${COLOR_RED}Error: Command failed with exit code %s: %s${COLOR_RESET}\n" "$exit_code" "$cmd" >&2
        exit $exit_code
    fi
}

# 打印用法
usage() {
    printf "Usage: %s [options]\n" "$0"
    printf "\n"
    printf "Version Options (at least one is required):\n"
    printf "  <major|minor|patch>       Increment the version number automatically.\n"
    printf "  -v, --version <version>   Specify the exact version number for the release.\n"
    printf "\n"
    printf "Control Options:\n"
    printf "  -c, --changelog <mode>    Generate a changelog. Mode can be 'latest' or 'all'.\n"
    printf "  -t, --tag                 Create a git tag for the release.\n"
    printf "  -r, --release               Create a release on GitLab/GitHub.\n"
    printf "  -d, --deploy               Build and deploy artifacts.\n"
    printf "  -P, --central               Used with --deploy to publish to Maven Central via 'release' profile.\n"
    printf "  -g, --gh-pages              Build and deploy the maven site to the gh-pages branch (GitHub only).\n"
    printf "  -n, --dry-run              Simulate the release process without making any actual changes.\n"
    printf "  -a, --allow-dirty          Allow the script to run even with uncommitted changes.\n"
    printf "  -h, --help                 Show this help message.\n"
    printf "\n"
    printf "Examples:\n"
    printf "  # Release the current snapshot version (e.g. 4.2.11-SNAPSHOT -> 4.2.11)\n"
    printf "  bash $0\n"
    printf "\n"
    printf "  # Perform a patch release (e.g. 4.2.11-SNAPSHOT -> 4.2.12)\n"
    printf "  bash $0 -v patch\n"
    printf "\n"
    printf "  # Perform a major release with deploy and tag\n"
    printf "  bash $0 -v major -d -t\n"
    printf "\n"
    printf "  # Release a specific version\n"
    printf "  bash $0 -v 4.2.12 -r -t\n"
    printf "\n"
    printf "  # Print the full changelog and exit\n"
    printf "  bash $0 -c all\n"
    exit 0
}

# 计算下一个版本
calculate_next_version_from_base() {
    local release_type="$1"
    local base_version="$2"

    local major minor patch
    IFS='.' read -r major minor patch <<< "$base_version"

    case "$release_type" in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
    esac

    NEW_VERSION="$major.$minor.$patch"
}

# 从发布版本计算下一个快照版本
calculate_next_snapshot_version() {
    local release_version="$1"
    local major minor patch
    IFS='.' read -r major minor patch <<< "$release_version"
    patch=$((patch + 1))
    echo "$major.$minor.$patch-SNAPSHOT"
}

# 解析参数
parse_args() {
    # 1. Get current project version from pom.xml
    printf "\n${COLOR_BLUE}Analyzing project version...${COLOR_RESET}\n"
    CURRENT_VERSION=$(get_current_version)
    if [ -z "$CURRENT_VERSION" ]; then
        printf "${COLOR_RED}Error: Could not determine current project version from pom.xml.${COLOR_RESET}\n" >&2
        exit 1
    fi

    local current_release_version
    current_release_version=$(echo "$CURRENT_VERSION" | sed 's/-SNAPSHOT//')

    # 2. Parse command line flags
    local non_flag_args=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--changelog)
                PERFORM_CHANGELOG=true
                # Check if the next argument is a valid mode and not another flag
                if [ -n "$2" ] && [[ "$2" != -* ]] && { [[ "$2" == "all" ]] || [[ "$2" == "latest" ]]; }; then
                    CHANGELOG_MODE="$2"
                    shift 2
                else
                    # Default to 'latest' if no valid mode is provided
                    CHANGELOG_MODE="latest"
                    shift 1
                fi
                ;;
            -v|--version)
                if [ -z "$2" ] || [[ "$2" == -* ]]; then
                    printf "${COLOR_RED}Error: --version option requires an argument.${COLOR_RESET}\n" >&2
                    usage
                    exit 1
                fi
                SPECIFIC_VERSION=$2
                shift 2
                ;;
            -t|--tag)
                PERFORM_TAG=true
                shift
                ;;
            -r|--release)
                PERFORM_RELEASE=true
                shift
                ;;
            -d|--deploy)
                PERFORM_DEPLOY=true
                shift
                ;;
            -P|--central)
                PERFORM_CENTRAL_DEPLOY=true
                shift
                ;;
            -g|--gh-pages)
                PERFORM_GHPAGES_DEPLOY=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -a|--allow-dirty)
                ALLOW_DIRTY=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                printf "Unknown option: %s\n" "$1"
                usage
                exit 1
                ;;
            *)
                non_flag_args+=("$1")
                shift
                ;;
        esac
    done

    # Restore positional parameters
    set -- "${non_flag_args[@]}"

    # 3. Handle version specification (positional or from -v)
    # Positional arguments (major, minor, patch)
    if [ -n "$1" ]; then
        if [ -n "$SPECIFIC_VERSION" ]; then
            printf "${COLOR_RED}Error: You cannot specify a version type ('%s') and a specific version ('%s') at the same time.${COLOR_RESET}\n" "$1" "$SPECIFIC_VERSION" >&2
            usage
            exit 1
        fi
        VERSION_MODE="$1"
        case $VERSION_MODE in
            major|minor|patch)
                NEW_VERSION=$(semver_increment "$current_release_version" "$VERSION_MODE")
                ;;
            *)
                printf "${COLOR_RED}Error: Invalid version type specified: '%s'. Must be 'major', 'minor', or 'patch'.${COLOR_RESET}\n" "$VERSION_MODE" >&2
                usage
                exit 1
                ;;
        esac
    elif [ -n "$SPECIFIC_VERSION" ]; then
        # -v <version> was used
        VERSION_MODE="custom"
        NEW_VERSION="$SPECIFIC_VERSION"
    fi

    # Default case: if no version is specified, use the current snapshot version as the release version.
    if [ -z "$VERSION_MODE" ] && [ -z "$SPECIFIC_VERSION" ]; then
        if [[ ! "$CURRENT_VERSION" == *"-SNAPSHOT" ]]; then
            printf "${COLOR_RED}Error: The current version %s is not a snapshot version.${COLOR_RESET}\n" "$CURRENT_VERSION"
            printf "To release a non-snapshot version, you must specify the version type ('major', 'minor', 'patch') or a specific version number with -v.\n" >&2
            exit 1
        fi
        VERSION_MODE="custom"
        NEW_VERSION="$current_release_version"
    fi

    # 4. Final check: Ensure some version was set
    if [ -z "$NEW_VERSION" ]; then
        printf "${COLOR_RED}Error: No release version could be determined.${COLOR_RESET}\n" >&2
        printf "You must specify a version type ('major', 'minor', 'patch'), a specific version ('-v X.Y.Z'), or be on a SNAPSHOT version.\n" >&2
        usage
        exit 1
    fi

    # 5. Calculate and log next snapshot version
    NEXT_SNAPSHOT_VERSION="$(semver_increment "$NEW_VERSION" "patch")-SNAPSHOT"

    printf "✅ Version analysis complete.\n"
    printf "  - Current: %s\n" "$CURRENT_VERSION"
    printf "  - Release: %s\n" "$NEW_VERSION"
    printf "  - Next Snapshot: %s\n" "$NEXT_SNAPSHOT_VERSION"
}

# 删除本地和远程的 tag
delete_tag() {
    local version="$1"
    local tag_name="v${version}"

    printf "${COLOR_YELLOW}Attempting to delete tag '%s'...${COLOR_RESET}\n" "$tag_name"

    # Delete local tag
    if git tag -d "$tag_name" >/dev/null 2>&1; then
        printf "  - Deleted local tag: %s\n" "$tag_name"
    else
        printf "${COLOR_YELLOW}Warning: Local tag '%s' not found or could not be deleted.${COLOR_RESET}\n" "$tag_name"
    fi

    # Delete remote tag
    if git push --delete origin "$tag_name" >/dev/null 2>&1; then
        printf "  - Deleted remote tag: %s\n" "$tag_name"
    else
        printf "${COLOR_YELLOW}Warning: Remote tag '%s' not found on origin or could not be deleted.${COLOR_RESET}\n" "$tag_name"
    fi
    printf "${COLOR_GREEN}Tag deletion process finished.${COLOR_RESET}\n"
}

# 获取当前 pom.xml 中的版本
get_current_version() {
    mvn -q help:evaluate -Dexpression=project.version -DforceStdout
}

# Increment a semantic version string (X.Y.Z)
semver_increment() {
    local version="$1"
    local part_to_inc="$2"
    local major minor patch

    # Use parameter expansion to split the version string
    major=${version%%.*}
    version=${version#*.}
    minor=${version%%.*}
    patch=${version#*.}

    case "$part_to_inc" in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            printf "Error: Invalid part to increment: %s\n" "$part_to_inc" >&2
            exit 1
            ;;
    esac

    echo "${major}.${minor}.${patch}"
}

# Deploy generated maven site to gh-pages branch
deploy_to_gh_pages() {
    printf "\n${COLOR_BLUE}Generating site...${COLOR_RESET}\n"
    if ! execute "mvn -ntp -B -U -DskipTests site site:stage"; then
        printf "${COLOR_RED}Error: Failed to generate maven site. Aborting gh-pages deployment.${COLOR_RESET}\n" >&2
        return
    fi
    printf "✅ Site generated successfully.\n"

    printf "\n${COLOR_BLUE}Deploying site to gh-pages branch...${COLOR_RESET}\n"

    if [ "$REPO_TYPE" != "github" ]; then
        printf "${COLOR_YELLOW}Warning: gh-pages deployment is only supported for GitHub repositories. Skipping.${COLOR_RESET}\n"
        return
    fi

    local site_dir="target/site"
    if [ ! -d "$site_dir" ]; then
        printf "${COLOR_RED}Error: Site directory '%s' not found. Please ensure 'mvn site' ran successfully.${COLOR_RESET}\n" "$site_dir"
        return
    fi

    local temp_dir
    temp_dir=$(mktemp -d)
    local repo_url
    repo_url=$(git config --get remote.origin.url)

    printf "Cloning repository into a temporary directory...\n"
    if ! git clone "$repo_url" "$temp_dir"; then
        printf "${COLOR_RED}Error: Failed to clone repository for gh-pages deployment.${COLOR_RESET}\n" >&2
        rm -rf "$temp_dir"
        return
    fi

    cd "$temp_dir" || exit

    if git ls-remote --exit-code --heads origin gh-pages >/dev/null 2>&1; then
        printf "Checking out existing 'gh-pages' branch...\n"
        execute "git checkout gh-pages"
    else
        printf "Creating new 'gh-pages' branch...\n"
        execute "git checkout --orphan gh-pages"
        execute "git rm -rf ."
    fi

    printf "Cleaning the working directory and copying new site content...\n"
    git rm -rf . >/dev/null 2>&1

    if ! rsync -a --delete --exclude '.git' "${PROJECT_ROOT}/${site_dir}/" .; then
        printf "${COLOR_RED}Error: Failed to copy site files with rsync.${COLOR_RESET}\n" >&2
        cd "$PROJECT_ROOT"
        rm -rf "$temp_dir"
        return
    fi

    if git diff-index --quiet HEAD --; then
        printf "Site content is unchanged. No new commit to 'gh-pages'.\n"
    else
        printf "Committing and pushing to 'gh-pages'...\n"
        execute "git add ."
        execute "git commit -m \"refactor: Update site for v${NEW_VERSION}\""
        if ! execute "git push origin gh-pages"; then
             printf "${COLOR_RED}Error: Failed to push to gh-pages branch.${COLOR_RESET}\n" >&2
        else
             printf "✅ Site deployed to gh-pages branch.\n"
        fi
    fi

    cd "$PROJECT_ROOT" || exit
    rm -rf "$temp_dir"
    printf "Cleaned up temporary directory.\n"
}

# Interactively handle an existing Git tag
handle_existing_tag() {
    local tag_name="$1"
    local location="$2" # "local" or "remote"
    local answer
 
    read -p "Tag '${tag_name}' already exists on ${location}. Do you want to delete it and proceed? (Y/n) " answer
    # Default to 'Y' if the user just presses Enter
    answer=${answer:-Y}
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        printf "Deleting ${location} tag '${tag_name}'...\n"
        delete_tag "$NEW_VERSION"
    else
        printf "${COLOR_RED}Aborting release. Please handle the existing tag manually.${COLOR_RESET}\n"
        exit 1
    fi
}

# 检查 git 工作目录是否干净
check_if_git_dirty() {
    if [ "$ALLOW_DIRTY" = false ]; then
        if ! git diff-index --quiet HEAD --; then
            printf "${COLOR_RED}Error: Your working directory is not clean. Please commit or stash your changes.${COLOR_RESET}\n"
            printf "You can use the -a or --allow-dirty flag to override this check.\n"
            exit 1
        fi
        printf "${COLOR_GREEN}Git working directory is clean.${COLOR_RESET}\n"
    else
        printf "${COLOR_YELLOW}Warning: Running with a dirty working directory.${COLOR_RESET}\n"
    fi
}

# 生成 changelog 内容
generate_changelog_content() {
    local latest_tag=""
    if [ "$CHANGELOG_MODE" = "latest" ]; then
        latest_tag=$(git describe --tags --abbrev=0 2>/dev/null)
        if [ -z "$latest_tag" ]; then
            printf "${COLOR_RED}Error: Changelog mode is 'latest' but no previous tags were found.${COLOR_RESET}\n" >&2
            printf "Please use '-c all' to generate from all commits, or create a tag first.\n" >&2
            exit 1
        fi
    fi

    local changelog_content=""
    local had_changes=false

    # Two parallel arrays for bash compatibility
    local C_TYPE_KEYS=("feat" "fix" "docs" "style" "refactor" "perf" "test" "build" "ci" "chore" "revert")
    local C_TYPE_VALUES=("✨ Features" "🐛 Bug Fixes" "📝 Documentation" "🎨 Code Style" "🔨 Code Refactoring" "⚡️ Performance Improvements" "✅ Tests" "📦 Build System" "🤖 Continuous Integration" "🧹 Chores" "⏪ Reverts")

    if [ -n "$latest_tag" ]; then
        # Print status to stderr so it doesn't get captured by the command substitution
        printf "📝 Generating changelog from commits since tag ${COLOR_YELLOW}%s${COLOR_RESET}...\n" "$latest_tag" >&2
    else
        printf "📝 Generating changelog from all commits.\n" >&2
    fi

    for i in "${!C_TYPE_KEYS[@]}"; do
        local type_key="${C_TYPE_KEYS[$i]}"
        local type_value="${C_TYPE_VALUES[$i]}"
        local commits

        if [ -n "$latest_tag" ]; then
            commits=$(git log "${latest_tag}"..HEAD --pretty=format:"* %s (%h)" --grep="^${type_key}:")
        else
            commits=$(git log --pretty=format:"* %s (%h)" --grep="^${type_key}:")
        fi

        if [ -n "$commits" ]; then
            had_changes=true
            changelog_content="${changelog_content}\n### ${type_value}\n\n${commits}\n"
        fi
    done

    echo -e "$changelog_content"
}


# 预检
pre_flight_checks() {
    printf "\n${COLOR_BLUE}Check env...${COLOR_RESET}\n"

    # Step 1: Check if inside a git repository
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        printf "${COLOR_RED}Error: This script must be run from a Git repository.${COLOR_RESET}\n" >&2
        exit 1
    fi
    printf "✅ Verified running inside a Git repository.\n"

    # Step 2: Get current branch and check for uncommitted changes
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    printf "Operating on branch: ${COLOR_YELLOW}%s${COLOR_RESET}\n" "$CURRENT_BRANCH"
    check_if_git_dirty

    # Step 3: Fetch all tags and changes from remote
    printf "\n${COLOR_BLUE}Updating from remote repository...${COLOR_RESET}\n"
    if ! git fetch --all --tags; then
       printf "${COLOR_RED}Error: Failed to fetch from remote. Check your connection and repository URL.${COLOR_RESET}\n"
       exit 1
    fi
    printf "✅ Successfully fetched from remote.\n"

    # Step 4: Check if local branch is up-to-date
    LOCAL_SHA=$(git rev-parse HEAD)
    REMOTE_SHA=$(git rev-parse "origin/${CURRENT_BRANCH}" 2>/dev/null) # Assumes remote is 'origin'

    if [ -z "$REMOTE_SHA" ]; then
        printf "${COLOR_YELLOW}Warning: Could not determine remote branch for '%s'. Skipping 'up-to-date' check.${COLOR_RESET}\n" "$CURRENT_BRANCH"
    else
        BASE_SHA=$(git merge-base HEAD "origin/${CURRENT_BRANCH}")
        if [ "$LOCAL_SHA" = "$REMOTE_SHA" ]; then
            printf "✅ Local branch is up-to-date with remote.\n"
        elif [ "$LOCAL_SHA" = "$BASE_SHA" ]; then
            printf "${COLOR_RED}Error: Local branch '%s' is behind remote. Please pull the latest changes.${COLOR_RESET}\n" "$CURRENT_BRANCH"
            exit 1
        elif [ "$REMOTE_SHA" != "$BASE_SHA" ]; then
             printf "${COLOR_RED}Error: Local branch '%s' has diverged from remote. Please rebase or merge.${COLOR_RESET}\n" "$CURRENT_BRANCH"
             exit 1
        fi
    fi

    # Step 5: Check if release tag already exists, only if we intend to tag
    if [ "$PERFORM_TAG" = true ]; then
      local tag_to_check="v${NEW_VERSION}"
      printf "\n${COLOR_BLUE}Checking for existing tag '%s'...${COLOR_RESET}\n" "$tag_to_check"
      # Check local tags
      if git rev-parse "$tag_to_check" >/dev/null 2>&1; then
          printf "${COLOR_YELLOW}Warning: Tag '%s' already exists locally.${COLOR_RESET}\n" "$tag_to_check"
          handle_existing_tag "$tag_to_check"
      fi

      # Check remote tags
      if git ls-remote --tags origin | grep -q "refs/tags/${tag_to_check}$"; then
          printf "${COLOR_YELLOW}Warning: Tag '%s' already exists on remote 'origin'.${COLOR_RESET}\n" "$tag_to_check"
          handle_existing_tag "$tag_to_check" "remote"
      fi
      printf "✅ Tag '%s' does not exist locally or on remote 'origin'.\n" "$tag_to_check"
    fi

    # Step 6: Check for necessary commands and determine repo type if releasing
    if [ "$PERFORM_RELEASE" = true ] || [ "$PERFORM_DEPLOY" = true ] || [ "$PERFORM_GHPAGES_DEPLOY" = true ]; then
        local repo_url
        repo_url=$(git config --get remote.origin.url)
        if [[ $repo_url == *github.com* ]]; then
            REPO_TYPE="github"
        elif [[ $repo_url == *gitlab* ]]; then
            REPO_TYPE="gitlab"
            if [[ $repo_url == git@* ]]; then
                REPO_HOST=$(echo "$repo_url" | cut -d'@' -f2 | cut -d':' -f1)
                GITLAB_PROJECT_PATH_ENCODED=$(echo "$repo_url" | cut -d':' -f2 | sed 's/\.git$//' | sed 's/\//%2F/g')
            elif [[ $repo_url == https://* ]]; then
                REPO_HOST=$(echo "$repo_url" | cut -d'/' -f3)
                GITLAB_PROJECT_PATH_ENCODED=$(echo "$repo_url" | cut -d'/' -f4- | sed 's/\.git$//' | sed 's/\//%2F/g')
            fi
        else
            printf "${COLOR_YELLOW}Warning: Could not determine repository type from URL. Release creation may fail.${COLOR_RESET}\n"
        fi

        if [ "$PERFORM_GHPAGES_DEPLOY" = true ]; then
            if ! command -v rsync &> /dev/null; then
                printf "${COLOR_RED}Error: 'rsync' is required for deploying to gh-pages but is not found.${COLOR_RESET}\n"
                exit 1
            fi
            printf "✅ Command 'rsync' is available.\n"

            if [ "$REPO_TYPE" != "github" ]; then
                printf "${COLOR_YELLOW}Warning: --gh-pages is specified, but this does not appear to be a GitHub repository. This step will be skipped.${COLOR_RESET}\n"
            fi
        fi
        if [ "$PERFORM_RELEASE" = true ]; then
            if [ "$REPO_TYPE" = "github" ]; then
                if ! command -v gh &> /dev/null; then
                    printf "${COLOR_RED}Error: GitHub CLI 'gh' not found, but is required for creating a GitHub release.${COLOR_RESET}\n" >&2
                    exit 1
                fi
                printf "✅ Command 'gh' is available.\n"
            elif [ "$REPO_TYPE" = "gitlab" ]; then
                if ! command -v curl &> /dev/null || ! command -v jq &> /dev/null; then
                    printf "${COLOR_RED}Error: 'curl' and 'jq' are required for creating a GitLab release.${COLOR_RESET}\n" >&2
                    exit 1
                fi
                if [ -z "$GITLAB_TOKEN" ]; then
                    printf "${COLOR_RED}Error: GITLAB_TOKEN environment variable is not set.${COLOR_RESET}\n" >&2
                    exit 1
                fi
                printf "✅ Commands 'curl', 'jq', and GITLAB_TOKEN are available.\n"
            fi
        fi
    fi
}

# -- 变更日志生成核心函数 --
_generate_changelog_for_range() {
    local commit_range="$1"
    local sections=()

    local COMMITS
    COMMITS=$(git log "$commit_range" --pretty=format:"- %s" --reverse | grep -vE "^- (\[CI Skip\]|Merge|\[maven-release-plugin\])" || true)

    if [ -z "$COMMITS" ]; then
        return
    fi

    for i in "${!C_TYPE_KEYS[@]}"; do
        local type="${C_TYPE_KEYS[$i]}"
        local MATCHING_COMMITS
        MATCHING_COMMITS=$(echo "$COMMITS" | grep -i "^- ${type}\(([^)]*)\)\?:" || true)
        if [ -n "$MATCHING_COMMITS" ]; then
            local section_content
            section_content=$(printf "### %s\n\n%s" "${C_TYPE_VALUES[$i]}" "$MATCHING_COMMITS")
            sections+=("$section_content")
        fi
    done

    if [ ${#sections[@]} -gt 0 ]; then
        # Add a leading newline for proper spacing within the full file
        printf "\n"
        
        for i in "${!sections[@]}"; do
            printf "%s" "${sections[$i]}"
            if [ $i -lt $((${#sections[@]} - 1)) ]; then
                printf "\n\n"
            fi
        done

        printf "\n"
    fi
}

# 生成完整的变更日志 (用于 --changelog 标志)
generate_full_changelog() {
    local mode="$1" # 'all' or 'latest'
    local TAGS
    TAGS=$(git tag --sort=-v:refname)
    local RELEASES

    RELEASES=("HEAD")
    if [ "$mode" == "all" ]; then
        RELEASES+=(${TAGS})
    fi

    for i in $(seq 0 $((${#RELEASES[@]} - 1))); do
        local CURRENT_REF="${RELEASES[$i]}"
        local PREV_REF

        if [ $i -lt $((${#RELEASES[@]} - 1)) ]; then
            PREV_REF=${RELEASES[$i+1]}
        else
            PREV_REF=$(git rev-list --max-parents=0 HEAD 2>/dev/null || echo "")
        fi

        local VERSION DATE COMMIT_RANGE
        if [ "$CURRENT_REF" == "HEAD" ]; then
            VERSION="$(get_current_version | sed 's/-SNAPSHOT//') (Unreleased)"
            DATE=$(date +%Y-%m-%d)
            COMMIT_RANGE="${PREV_REF}..HEAD"
        else
            VERSION=$(echo "$CURRENT_REF" | sed 's/^v//')
            DATE=$(git log -1 --format=%cs "$CURRENT_REF")
            COMMIT_RANGE="${PREV_REF}..${CURRENT_REF}"
        fi
        
        local changelog_part
        changelog_part=$(_generate_changelog_for_range "$COMMIT_RANGE")

        if [ -n "$changelog_part" ]; then
            printf "## [%s] - %s\n" "$VERSION" "$DATE"
            echo "$changelog_part"
        fi
    done
}

# 打印发布计划并请求用户确认
confirm_plan() {
    printf "\n${COLOR_BLUE}Confirm Release Plan...${COLOR_RESET}\n"

    local changelog_status="No"
    if [ "$PERFORM_CHANGELOG" = true ]; then
        changelog_status="Yes ($CHANGELOG_MODE)"
    fi

    local tag_status="No"
    if [ "$PERFORM_TAG" = true ]; then
        tag_status="Yes (v${NEW_VERSION})"
    fi

    local release_status="No"
    if [ "$PERFORM_RELEASE" = true ]; then
        local repo_type_display="GitLab/GitHub" # Fallback
        if [ -n "$REPO_TYPE" ]; then
            repo_type_display=$(tr '[:lower:]' '[:upper:]' <<< "${REPO_TYPE:0:1}")${REPO_TYPE:1}
        fi
        release_status="Yes (${repo_type_display})"
    fi

    local deploy_status="No"
    if [ "$PERFORM_DEPLOY" = true ]; then
        if [ "$PERFORM_CENTRAL_DEPLOY" = true ]; then
            deploy_status="Yes (Central)"
        else
            deploy_status="Yes (Local)"
        fi
    fi

    local ghp_status="No"
    if [ "$PERFORM_GHPAGES_DEPLOY" = true ]; then
        ghp_status="Yes (GitHub Pages)"
    fi

    # --- Print plan ---
    printf "${COLOR_BOLD}------- Release Plan -------${COLOR_RESET}\n"
    printf "This script will perform the following actions based on your input:\n"
    local label_width=32
    printf "  - %-${label_width}s: %s\n" "Current Project Version" "$CURRENT_VERSION"
    printf "  - %-${label_width}s: %s (%s)\n" "New Release Version" "${NEW_VERSION}" "$VERSION_MODE"
    printf "  - %-${label_width}s: %s\n" "Next Snapshot Version" "${NEXT_SNAPSHOT_VERSION}"
    printf "  - %-${label_width}s: %s\n" "Update CHANGELOG.md" "$changelog_status"
    printf "  - %-${label_width}s: %s\n" "Create git tag" "$tag_status"
    printf "  - %-${label_width}s: %s\n" "Create Release" "$release_status"
    printf "  - %-${label_width}s: %s\n" "Deploy artifacts to Repository" "$deploy_status"
    if [ "$REPO_TYPE" = "github" ]; then
      printf "  - %-${label_width}s: %s\n" "Deploy site to gh-pages" "$ghp_status"
    fi

    if [ "$DRY_RUN" = true ]; then
        printf "\n${COLOR_YELLOW_BG}${COLOR_BLACK} DRY RUN MODE - NO CHANGES WILL BE MADE ${COLOR_RESET}\n"
        return
    fi
  
    read -p "Do you want to proceed with this release plan? [Y/n]: " -r choice
    # Default to 'Y' if the user just presses Enter
    choice=${choice:-Y}
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        printf "${COLOR_RED}Release aborted by user.${COLOR_RESET}\n"
        exit 1
    fi
  
    printf "${COLOR_GREEN}✅ Release plan confirmed. Starting release process...${COLOR_RESET}\n"
}

# 更新 CHANGELOG.md 文件
update_changelog() {
    printf "\n${COLOR_BLUE}Updating CHANGELOG.md...${COLOR_RESET}\n"
    local changelog_file="CHANGELOG.md"
    local release_header="## [${NEW_VERSION}] - $(date +'%Y-%m-%d')"

    # Check if the changelog entry for this version already exists
    if [ -f "$changelog_file" ] && grep -q -F "[${NEW_VERSION}]" "$changelog_file"; then
        printf "${COLOR_YELLOW}Warning: Changelog entry for version %s already exists. Skipping update.${COLOR_RESET}\n" "$NEW_VERSION"
        return
    fi

    local new_content
    new_content=$(generate_changelog_content)

    if [ ! -f "$changelog_file" ]; then
        printf "File %s not found. Creating a new one with a default header.\n" "$changelog_file"
        # Using cat with a quoted EOF to prevent any variable expansion inside the heredoc
        cat > "$changelog_file" <<'EOF'
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

EOF
        # Now append the new version's content
        printf "\n%s\n%s\n" "$release_header" "$new_content" >> "$changelog_file"
        printf "✅ Changelog created and updated successfully.\n"
        return
    fi

    # Read the existing file and insert the new content after line 7
    local temp_file
    temp_file=$(mktemp)
    
    # Write the first 7 lines to the temp file
    head -n 7 "$changelog_file" > "$temp_file"
    
    # Append the new header and content
    printf "\n%s\n%s" "$release_header" "$new_content" >> "$temp_file"
    
    # Append the rest of the original file
    tail -n +8 "$changelog_file" >> "$temp_file"
    
    # Overwrite the original file
    mv "$temp_file" "$changelog_file"

    printf "✅ Changelog updated successfully.\n"
}

# --- Command Functions ---

commit_and_tag() {
    printf "\n${COLOR_BLUE}Committing release version and tagging...${COLOR_RESET}\n"
    local commit_message="release: v${NEW_VERSION}"

    # Always set the new version in pom files
    execute "mvn versions:set -DnewVersion=${NEW_VERSION} -DgenerateBackupPoms=false"

    # Add all changed files (pom.xml and possibly CHANGELOG.md)
    execute "git add ."

    # Commit only if there are staged changes
    if ! git diff-index --quiet --cached HEAD --; then
        execute "git commit -m \"refactor: ${commit_message}\""
    else
        printf "${COLOR_YELLOW}Warning: No changes to commit for release version.${COLOR_RESET}\n"
    fi

    if [ "$PERFORM_TAG" = true ]; then
        execute "git tag -a \"v${NEW_VERSION}\" -m \"Release v${NEW_VERSION}\""
        execute "git push --tags"
    fi
}

build_and_deploy() {
    printf "\n${COLOR_BLUE}Building artifacts...${COLOR_RESET}\n"
    local mvn_command="mvn -ntp -B -U -DskipTests clean install"
    if [ "$PERFORM_DEPLOY" = true ]; then
        mvn_command="${mvn_command} deploy"
    fi

    if [ "$PERFORM_CENTRAL_DEPLOY" = true ]; then
        execute "${mvn_command} -Prelease"
    else
        execute "${mvn_command}"
    fi
}

find_release_artifacts() {
    # Search for release assets in any 'target' directory within the project.
    # This correctly handles multi-module Maven projects.
    # We specifically look for .jar, .asc, and pom.xml files.
    # We exclude source and javadoc jars, and files from maven-archiver/surefire-reports.
    find . -path '*/target/*' -type f \( -name "*.jar" -o -name "*.asc" -o -name "pom.xml" \)
}

create_release() {
    printf "\n${COLOR_BLUE}Creating Release...${COLOR_RESET}\n"

    local tag_name="v${NEW_VERSION}"
    local changelog_for_release
    changelog_for_release=$(generate_changelog_content)

    local artifacts=()
    if [ -d "target" ]; then
        mapfile -t artifacts < <(find_release_artifacts)
    fi

    if [ "$REPO_TYPE" = "gitlab" ]; then
        if [ ${#artifacts[@]} -gt 0 ]; then
            printf "Uploading ${#artifacts[@]} artifact(s) to GitLab project to generate links...\n"
            local asset_links_markdown="\n\n### Assets\n"
            local has_assets=false
            local upload_url="https://${REPO_HOST}/api/v4/projects/${GITLAB_PROJECT_PATH_ENCODED}/uploads"

            for artifact in "${artifacts[@]}"; do
                printf "  - Uploading %s...\n" "$artifact"
                
                local upload_response
                upload_response=$(curl -s -w "\n%{http_code}" --request POST \
                    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
                    --form "file=@${artifact}" \
                    "$upload_url")
                
                local upload_http_body
                upload_http_body=$(echo "$upload_response" | sed '$d')
                local upload_http_status
                upload_http_status=$(echo "$upload_response" | tail -n1)

                if [ "$upload_http_status" -eq 201 ]; then
                    local markdown_link
                    markdown_link=$(echo "$upload_http_body" | jq -r '.markdown')
                    asset_links_markdown+="- ${markdown_link}\n"
                    has_assets=true
                    printf "    ${COLOR_GREEN}Success.${COLOR_RESET}\n"
                else
                    printf "    ${COLOR_RED}Error: Failed to upload artifact %s. Status: %s\nBody: %s${COLOR_RESET}\n" "$artifact" "$upload_http_status" "$upload_http_body"
                fi
            done

            if [ "$has_assets" = true ]; then
                changelog_for_release+="${asset_links_markdown}"
            fi
        fi

        local api_url="https://${REPO_HOST}/api/v4/projects/${GITLAB_PROJECT_PATH_ENCODED}/releases"
        local json_payload
        json_payload=$(jq -n \
            --arg name "${tag_name}" \
            --arg tag_name "${tag_name}" \
            --arg description "$changelog_for_release" \
            --arg ref "${tag_name}" \
            '{name: $name, tag_name: $tag_name, description: $description, ref: $ref}')

        printf "✅ Creating GitLab release for tag %s...\n" "$tag_name"
        
        local http_response
        http_response=$(curl -s -w "\n%{http_code}" --request POST --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
            --header "Content-Type: application/json" --data "$json_payload" "$api_url")
        
        local http_body
        http_body=$(echo "$http_response" | sed '$d')
        local http_status
        http_status=$(echo "$http_response" | tail -n1)

        if [ "$http_status" -ge 200 ] && [ "$http_status" -lt 300 ]; then
            printf "${COLOR_GREEN}Successfully created GitLab release.${COLOR_RESET}\n"
        else
            printf "${COLOR_RED}Error: Failed to create GitLab release. Status: %s\nBody: %s${COLOR_RESET}\n" "$http_status" "$http_body"
            exit 1
        fi

    elif [ "$REPO_TYPE" = "github" ]; then
        printf "✅ Creating GitHub release for tag %s...\n" "$tag_name"
        
        # Use a temporary file for the changelog to pass to gh, avoiding issues with special characters and command length
        local changelog_tmp_file
        changelog_tmp_file=$(mktemp)
        printf "%s" "$changelog_for_release" > "$changelog_tmp_file"

        local gh_command="gh release create \"$tag_name\" --title \"${tag_name}\" --notes-file \"$changelog_tmp_file\""

        if [ ${#artifacts[@]} -gt 0 ]; then
            printf "Attaching ${#artifacts[@]} artifact(s)...\n"
            # Append artifact paths, quoting them for safety since execute uses eval
            for artifact in "${artifacts[@]}"; do
                gh_command+=" '$artifact'"
            done
        else
            printf "${COLOR_YELLOW}Warning: No release artifacts found to upload.${COLOR_RESET}\n"
        fi
        
        execute "$gh_command"
        rm "$changelog_tmp_file"
    else
        printf "${COLOR_YELLOW}Warning: Skipping release creation. Unsupported repository type: '%s'.${COLOR_RESET}\n" "$REPO_TYPE"
    fi
}

set_to_next_snapshot() {
    printf "\n${COLOR_BLUE}Setting version to next snapshot...${COLOR_RESET}\n"
    execute "mvn versions:set -DnewVersion=${NEXT_SNAPSHOT_VERSION} -DgenerateBackupPoms=false"
    execute "git add ."
    if ! git diff-index --quiet HEAD --; then
        execute "git commit -m \"refactor: Prepare for next development iteration\""
    else
        printf "${COLOR_YELLOW}Warning: No changes to commit for next snapshot version.${COLOR_RESET}\n"
    fi
}

push_final_changes() {
    printf "\n${COLOR_BLUE}Pushing branch to origin...${COLOR_RESET}\n"
    if [ "$PERFORM_TAG" = true ]; then
        printf "Pushing branch '%s' and tag 'v%s' atomically.\n" "$CURRENT_BRANCH" "$NEW_VERSION"
        execute "git push --atomic origin ${CURRENT_BRANCH} v${NEW_VERSION}"
    else
        printf "Pushing branch '%s'.\n" "$CURRENT_BRANCH"
        execute "git push origin ${CURRENT_BRANCH}"
    fi
}

# --- Main Execution ---

main() {
    trap cleanup EXIT
 
    # Ensure we are in a git repository root
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        printf "${COLOR_RED}Error: This script must be run from the root of a Git repository.${COLOR_RESET}\n" >&2
        exit 1
    fi
    PROJECT_ROOT=$(git rev-parse --show-toplevel)
    cd "$PROJECT_ROOT" || exit 1
 
    parse_args "$@"
    pre_flight_checks
    confirm_plan
 
    if [ "$PERFORM_CHANGELOG" = true ] && [ ! -f "CHANGELOG.md" ]; then
        update_changelog
    fi
 
    commit_and_tag
    build_and_deploy
    set_to_next_snapshot
    push_final_changes
 
    if [ "$PERFORM_RELEASE" = true ]; then
        create_release
    fi
 
    if [ "$PERFORM_GHPAGES_DEPLOY" = true ]; then
        deploy_gh_pages
    fi

    printf "\n${COLOR_GREEN}✅ Release process completed successfully!${COLOR_RESET}\n"
}

# --- Script Entrypoint ---
main "$@"
