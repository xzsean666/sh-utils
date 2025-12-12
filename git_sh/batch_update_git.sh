#!/bin/bash

# Batch update Git remote URLs from AstridTechnologies to 7pm-git
# Usage: ./batch_update_git.sh <folder_path>
# Example: ./batch_update_git.sh /home/sean/Astrid/trading

# Configuration variables
OLD_ORG="AstridTechnologies"
NEW_ORG="7pm-git"

if [ $# -ne 1 ]; then
    echo "Usage: $0 <folder_path>"
    echo "Example: $0 /home/sean/Astrid/trading"
    exit 1
fi

FOLDER=$1

if [ ! -d "$FOLDER" ]; then
    echo "Error: $FOLDER is not a valid directory"
    exit 1
fi

echo "Starting batch update for Git repos in $FOLDER (from $OLD_ORG to $NEW_ORG)"

# Find all Git repositories recursively
find "$FOLDER" -type d -name ".git" | while read -r git_dir; do
    repo_dir=$(dirname "$git_dir")
    echo "Processing: $repo_dir"
    cd "$repo_dir"
    current_url=$(git remote get-url origin 2>/dev/null)
    if [ $? -eq 0 ] && [[ $current_url == *$OLD_ORG* ]]; then
        new_url=$(echo "$current_url" | sed "s/$OLD_ORG/$NEW_ORG/")
        echo "  Updating remote URL from: $current_url"
        echo "  To: $new_url"
        git remote set-url origin "$new_url"
        echo "  Done."
    else
        echo "  Skipping: No $OLD_ORG remote or not a Git repo."
    fi
    cd "$FOLDER"
done

echo "Batch update completed."