#!/bin/bash

# Release Script - Automates the Maven project release process
# Features: Version management, Changelog generation, Git operations, GitLab integration

set -e

# === COLOR DEFINITIONS ===
declare -r RED='\033[0;31m'
declare -r GREEN='\033[0;32m'
declare -r YELLOW='\033[0;33m'
declare -r BLUE='\033[0;34m'
declare -r CYAN='\033[0;36m'
declare -r BOLD='\033[1m'
declare -r RESET='\033[0m'

# === ICONS ===
declare -r ICON_SUCCESS="✅"
declare -r ICON_ERROR="❌"
declare -r ICON_WARNING="⚠️"
declare -r ICON_ROCKET="🚀"
declare -r ICON_TAG="🏷️"
declare -r ICON_DOC="📝"

# === CONFIGURATION ===
declare -ra COMMIT_TYPES=("feat" "fix" "docs" "style" "refactor" "perf" "test" "build" "ci" "chore" "revert")
declare -ra CHANGELOG_HEADERS=("✨ Features" "🐛 Bug Fixes" "📝 Documentation" "🎨 Code Style" "🔨 Code Refactoring" "⚡️ Performance Improvements" "✅ Tests" "📦 Build System" "🤖 Continuous Integration" "🧹 Chores" "⏪ Reverts")

# === GLOBAL VARIABLES ===
declare NEW_VERSION=""
declare PERFORM_CHANGELOG=false
declare DRY_RUN=false
declare ALLOW_DIRTY=false
declare CHANGELOG_MODE="latest"
declare CURRENT_BRANCH=""
declare CURRENT_VERSION=""
declare GITLAB_PROJECT_ID=""
declare GITLAB_TOKEN=""
declare GITLAB_HOST=""

# === UTILITY FUNCTIONS ===
log() {
    local level="$1"
    shift
    case "$level" in
        "info") echo -e "${BLUE}${RESET}$*" ;;
        "success") echo -e "${GREEN}${ICON_SUCCESS} ${RESET}$*" ;;
        "warning") echo -e "${YELLOW}${ICON_WARNING} ${RESET}$*" ;;
        "error") echo -e "${RED}${ICON_ERROR} ${RESET}$*" >&2 ;;
        "header") echo -e "\n${BLUE}${BOLD}$*${RESET}" ;;
    esac
}

separator() {
    echo -e "${CYAN}$(printf '%*s' 60 | tr ' ' '=')${RESET}"
}

execute() {
    local cmd="$1"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY RUN]${RESET} ${BOLD}$cmd${RESET}"
        return 0
    fi
    
    if ! eval "$cmd"; then
        log error "Command failed: $cmd"
        exit 1
    fi
}

# === VERSION MANAGEMENT ===
get_current_version() {
    mvn -q help:evaluate -Dexpression=project.version -DforceStdout
}

calculate_version() {
    local version_type="$1"
    local current_version="$2"
    local base_version="${current_version%-SNAPSHOT}"

    case "$version_type" in
        "major")
            local major=$(echo "$base_version" | cut -d. -f1)
            echo "$((major + 1)).0.0"
            ;;
        "minor")
            local major=$(echo "$base_version" | cut -d. -f1)
            local minor=$(echo "$base_version" | cut -d. -f2)
            echo "${major}.$((minor + 1)).0"
            ;;
        "patch")
            local major=$(echo "$base_version" | cut -d. -f1)
            local minor=$(echo "$base_version" | cut -d. -f2)
            local patch=$(echo "$base_version" | cut -d. -f3)
            echo "${major}.${minor}.$((patch + 1))"
            ;;
        *)
            if [[ "$version_type" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "$version_type"
            else
                log error "Invalid version format. Use X.Y.Z, major, minor, or patch"
                exit 1
            fi
            ;;
    esac
}

# === CHANGELOG GENERATION ===
generate_changelog_content() {
    local latest_tag=""
    [[ "$CHANGELOG_MODE" = "latest" ]] && latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    
    if [[ -n "$latest_tag" ]]; then
        log info "Generating changelog from commits since tag ${YELLOW}$latest_tag${RESET}"
    else
        log info "Generating changelog from all commits"
    fi

    local changelog_content=""
    for i in "${!COMMIT_TYPES[@]}"; do
        local type_key="${COMMIT_TYPES[$i]}"
        local type_value="${CHANGELOG_HEADERS[$i]}"
        
        local commits
        if [[ -n "$latest_tag" ]]; then
            commits=$(git log "${latest_tag}"..HEAD --pretty=format:"* %s (%h)" --grep="^${type_key}:")
        else
            commits=$(git log --pretty=format:"* %s (%h)" --grep="^${type_key}:")
        fi

        if [[ -n "$commits" ]]; then
            changelog_content="${changelog_content}"$'\n'"### ${type_value}"$'\n\n'"${commits}"$'\n'
        fi
    done

    printf '%s' "$changelog_content"
}

update_changelog() {
    log header "Updating CHANGELOG.md"
    local changelog_file="CHANGELOG.md"
    local release_header="## [${NEW_VERSION}] - $(date +'%Y-%m-%d')"

    if [[ ! -f "$changelog_file" ]]; then
        log info "Creating new CHANGELOG.md file"
        cat > "$changelog_file" << 'EOF'
# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


EOF
    fi

    if grep -q -F "[${NEW_VERSION}]" "$changelog_file"; then
        log warning "Changelog entry for version $NEW_VERSION already exists. Skipping update"
        return
    fi

    local new_content
    new_content=$(generate_changelog_content)

    if [[ -z "$new_content" ]]; then
        log warning "No new commits found for the changelog. Skipping update"
        return
    fi

    local temp_file
    temp_file=$(mktemp)
    head -n 6 "$changelog_file" > "$temp_file"
    
    {
        printf "\n%s\n" "$release_header"
        printf '%s\n' "$new_content"
    } >> "$temp_file"

    if [[ $(wc -l < "$changelog_file") -gt 6 ]]; then
        printf "\n" >> "$temp_file"
        tail -n +7 "$changelog_file" >> "$temp_file"
    fi

    mv "$temp_file" "$changelog_file"
    log success "Changelog updated successfully"
}

# === GIT OPERATIONS ===
check_git_status() {
    if [[ "$ALLOW_DIRTY" = false ]]; then
        if ! git diff-index --quiet HEAD --; then
            log error "Working directory is not clean. Use -a/--allow-dirty to override"
            exit 1
        fi
        log success "Git working directory is clean"
    else
        log warning "Running with a dirty working directory"
    fi
}

commit_changes() {
    log header "Updating version and committing changes"
    
    execute "mvn versions:set -DnewVersion=${NEW_VERSION} -DgenerateBackupPoms=false"
    
    [[ "$PERFORM_CHANGELOG" = true ]] && update_changelog
    
    execute "git add pom.xml CHANGELOG.md"
    
    if ! git diff-index --quiet --cached HEAD --; then
        execute "git commit -m \"chore: release version ${NEW_VERSION}\""
        log success "Changes committed successfully"
    else
        log warning "No changes to commit"
    fi
}

push_to_remote() {
    log header "Pushing branch to remote repository"
    
    local remote_branch
    remote_branch=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "")

    if [[ -z "$remote_branch" ]]; then
        execute "git push -u origin ${CURRENT_BRANCH}"
        log success "Branch pushed and upstream set"
    else
        execute "git push"
        log success "Branch pushed successfully"
    fi
}

create_and_push_tag() {
    log header "Creating and pushing tag"
    
    local tag_name="v${NEW_VERSION}"
    local tag_message="Release version ${NEW_VERSION}"

    if git rev-parse "$tag_name" >/dev/null 2>&1; then
        log warning "Tag $tag_name already exists. Skipping tag creation"
        return
    fi

    execute "git tag -a ${tag_name} -m \"${tag_message}\""
    execute "git push origin ${tag_name}"
    
    log success "Tag ${CYAN}$tag_name${RESET} created and pushed"
}

# === GITLAB INTEGRATION ===
detect_gitlab_repository() {
    local remote_url
    remote_url=$(git config --get remote.origin.url 2>/dev/null || echo "")

    [[ "$remote_url" != *"gitlab"* ]] && return 1

    local project_path=""
    if [[ "$remote_url" =~ https?://[^/]+/(.+)\.git$ ]]; then
        project_path="${BASH_REMATCH[1]}"
    elif [[ "$remote_url" =~ git@[^:]+:(.+)\.git$ ]]; then
        project_path="${BASH_REMATCH[1]}"
    elif [[ "$remote_url" =~ https?://[^/]+/(.+)$ ]]; then
        project_path="${BASH_REMATCH[1]}"
    elif [[ "$remote_url" =~ git@[^:]+:(.+)$ ]]; then
        project_path="${BASH_REMATCH[1]}"
    fi

    [[ -z "$project_path" ]] && return 1

    GITLAB_PROJECT_ID="${project_path//\//%2F}"
    
    if [[ "$remote_url" =~ https?://([^/]+)/ ]]; then
        GITLAB_HOST="${BASH_REMATCH[1]}"
    elif [[ "$remote_url" =~ git@([^:]+): ]]; then
        GITLAB_HOST="${BASH_REMATCH[1]}"
    fi

    return 0
}

get_gitlab_token() {
    [[ -n "$GITLAB_TOKEN" ]] && return 0
    
    local git_token
    git_token=$(git config --get gitlab.token 2>/dev/null || echo "")
    if [[ -n "$git_token" ]]; then
        GITLAB_TOKEN="$git_token"
        return 0
    fi

    [[ "$DRY_RUN" = true ]] && { GITLAB_TOKEN="dummy-token"; return 0; }

    echo -e "\n${YELLOW}GitLab Personal Access Token required for creating releases${RESET}"
    echo "Setup options:"
    echo "  1. Environment variable: export GITLAB_TOKEN=your_token"
    echo "  2. Git config: git config --global gitlab.token your_token"
    echo "  3. Enter it now (input will be hidden)"
    echo

    read -s -p "Enter GitLab Personal Access Token: " GITLAB_TOKEN
    echo

    [[ -z "$GITLAB_TOKEN" ]] && { log warning "No token provided. Skipping GitLab release"; return 1; }
    return 0
}

create_gitlab_release() {
    log header "Creating GitLab Release"
    
    if ! detect_gitlab_repository; then
        log info "Not a GitLab repository. Skipping GitLab release creation"
        return 0
    fi

    log info "Detected GitLab project: ${CYAN}${GITLAB_PROJECT_ID//%2F/\/}${RESET}"

    get_gitlab_token || return 1

    local tag_name="v${NEW_VERSION}"
    local release_name="Release ${NEW_VERSION}"
    local description="Release version $NEW_VERSION"
    
    [[ "$PERFORM_CHANGELOG" = true ]] && {
        local changelog_content
        changelog_content=$(generate_changelog_content)
        [[ -n "$changelog_content" ]] && description="## What's Changed\n\n$changelog_content"
    }

    local api_data
    api_data=$(cat <<EOF
{
    "name": "$release_name",
    "tag_name": "$tag_name",
    "description": "$description",
    "ref": "$CURRENT_BRANCH"
}
EOF
)

    local api_url="https://${GITLAB_HOST}/api/v4/projects/${GITLAB_PROJECT_ID}/releases"

    if [[ "$DRY_RUN" = true ]]; then
        echo -e "${YELLOW}[DRY RUN]${RESET} ${BOLD}curl -X POST $api_url${RESET}"
        log success "GitLab release would be created successfully"
        return 0
    fi

    local response http_code
    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$api_data" \
        "$api_url")

    http_code=$(echo "$response" | tail -n1)
    local response_body
    response_body=$(echo "$response" | head -n -1)

    if [[ "$http_code" -eq 201 ]]; then
        log success "GitLab Release created successfully!"
        local release_url
        release_url=$(echo "$response_body" | grep -o '"_links":{"self":"[^"]*"' | sed 's/.*"self":"\([^"]*\)".*/\1/' | sed 's/api\/v4\/projects\/[^/]*\/releases/releases/')
        [[ -n "$release_url" ]] && echo -e "🔗 Release URL: ${CYAN}$release_url${RESET}"
    else
        log error "Failed to create GitLab Release (HTTP $http_code)"
        echo "Response: $response_body" >&2
        return 1
    fi
}

# === VALIDATION AND CHECKS ===
pre_flight_checks() {
    log header "Performing pre-flight checks"

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log error "This script must be run from a Git repository"
        exit 1
    fi
    log success "Verified running inside a Git repository"

    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    log info "Operating on branch: ${YELLOW}$CURRENT_BRANCH${RESET}"
    
    if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
        log error "This script cannot be run on the main or master branch"
        echo "Please create a feature branch first and switch to it"
        exit 1
    fi
    log success "Branch check passed"

    if [[ ! "$CURRENT_VERSION" == *"-SNAPSHOT" ]]; then
        log error "The current version $CURRENT_VERSION is not a snapshot version"
        echo "This script is designed to transition a SNAPSHOT version to a final release version"
        exit 1
    fi
    log success "Current version is a SNAPSHOT"

    check_git_status
}

confirm_plan() {
    separator
    echo -e "${BOLD}${BLUE}${ICON_ROCKET} RELEASE PLAN${RESET}"
    separator
    
    local changelog_status="No"
    [[ "$PERFORM_CHANGELOG" = true ]] && changelog_status="Yes ($CHANGELOG_MODE)"
    
    local gitlab_release_status="No"
    detect_gitlab_repository && gitlab_release_status="Yes (${GITLAB_PROJECT_ID//%2F/\/})"

    printf "%-30s: %s\n" "Branch" "${YELLOW}$CURRENT_BRANCH${RESET}"
    printf "%-30s: %s\n" "Current Version" "$CURRENT_VERSION"
    printf "%-30s: ${GREEN}%s${RESET}\n" "New Release Version" "$NEW_VERSION"
    printf "%-30s: %s\n" "Update CHANGELOG.md" "$changelog_status"
    printf "%-30s: Yes\n" "Push to Remote"
    printf "%-30s: Yes (v${NEW_VERSION})\n" "Create and Push Tag"
    printf "%-30s: %s\n" "Create GitLab Release" "$gitlab_release_status"
    
    separator

    [[ "$DRY_RUN" = true ]] && {
        echo -e "\n${YELLOW}${ICON_WARNING} DRY RUN MODE - NO CHANGES WILL BE MADE${RESET}\n"
        return
    }

    read -p "$(echo -e "Do you want to proceed with this plan? [${GREEN}Y${RESET}/n]: ")" -r choice
    choice=${choice:-Y}
    [[ ! "$choice" =~ ^[Yy]$ ]] && { log error "Aborted by user"; exit 1; }
}

# === ARGUMENT PARSING ===
parse_args() {
    CURRENT_VERSION=$(get_current_version)
    [[ -z "$CURRENT_VERSION" ]] && { log error "Could not determine current project version from pom.xml"; exit 1; }

    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--changelog)
                PERFORM_CHANGELOG=true
                if [[ -n "$2" && "$2" != -* && ("$2" == "all" || "$2" == "latest") ]]; then
                    CHANGELOG_MODE="$2"
                    shift 2
                else
                    shift 1
                fi
                ;;
            -v|--version)
                [[ -z "$2" || "$2" == -* ]] && { log error "--version option requires an argument"; usage; }
                NEW_VERSION="$2"
                shift 2
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
                ;;
            *)
                log error "Unknown option: $1"
                usage
                ;;
        esac
    done

    if [[ -z "$NEW_VERSION" ]]; then
        NEW_VERSION="${CURRENT_VERSION%-SNAPSHOT}"
        log info "Auto-calculated Release Version: $NEW_VERSION"
    else
        NEW_VERSION=$(calculate_version "$NEW_VERSION" "$CURRENT_VERSION")
        log info "Release Version: $NEW_VERSION"
    fi
}

usage() {
    cat << EOF
Release Script - Automates Maven project release process

USAGE:
    $0 [options]

DESCRIPTION:
    Prepares the current feature branch for a release by updating the project 
    version from SNAPSHOT to release version, updating CHANGELOG.md, committing 
    changes, pushing to remote, creating tags, and creating GitLab releases.

OPTIONS:
    -v, --version <version>   Specify version: X.Y.Z format, or major/minor/patch
                             If not specified, removes -SNAPSHOT from current version
    -c, --changelog [mode]    Generate a changelog. Mode: 'latest' (default) or 'all'
    -n, --dry-run             Simulate the process without making actual changes
    -a, --allow-dirty         Allow running with uncommitted changes
    -h, --help                Show this help message

GITLAB INTEGRATION:
    Authentication options:
    • Environment variable: GITLAB_TOKEN
    • Git config: git config --global gitlab.token <token>
    • Interactive input during execution

EXAMPLES:
    # Use current version without -SNAPSHOT
    $0 -c
    
    # Specify exact version
    $0 -v 1.2.3 -c
    
    # Increment patch version
    $0 -v patch -c
    
    # Dry run to preview changes
    $0 -v minor -c --dry-run

EOF
    exit 0
}

# === MAIN EXECUTION ===
main() {
    echo -e "${BOLD}${BLUE}${ICON_ROCKET} Maven Release Script${RESET}"
    separator
    
    parse_args "$@"
    pre_flight_checks
    confirm_plan
    
    log header "Starting release process"
    
    commit_changes
    push_to_remote
    create_and_push_tag
    create_gitlab_release
    
    separator
    echo -e "${GREEN}${ICON_SUCCESS} ${BOLD}Release completed successfully!${RESET}"
    separator
    
    echo "Summary:"
    echo "  • Version updated from $CURRENT_VERSION to $NEW_VERSION"
    echo "  • Changes committed and pushed to branch: $CURRENT_BRANCH"
    echo "  • Tag v$NEW_VERSION created and pushed"
    
    detect_gitlab_repository && echo "  • GitLab Release created for project: ${GITLAB_PROJECT_ID//%2F/\/}"
    
    echo
    echo "Next steps:"
    echo "  1. Create a Pull Request to merge '$CURRENT_BRANCH' into 'main'"
    echo "  2. After PR is merged, the release will be complete"
    echo
}

# Bash version check
[[ -z "$BASH_VERSION" ]] && { echo "Error: This script must be run with Bash, not sh." >&2; exit 1; }

main "$@"
