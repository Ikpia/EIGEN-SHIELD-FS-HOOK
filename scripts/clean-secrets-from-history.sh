#!/bin/bash

# Script to remove secrets from git history
# WARNING: This rewrites git history and requires force push
# Only run this if you understand the implications

set -e

echo "⚠️  WARNING: This script will rewrite git history!"
echo "⚠️  Make sure you have a backup and coordinate with your team."
echo ""
read -p "Do you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Check if git-filter-repo is installed
if ! command -v git-filter-repo &> /dev/null; then
    echo "git-filter-repo not found. Installing..."
    pip install git-filter-repo || {
        echo "Failed to install git-filter-repo. Please install manually:"
        echo "  pip install git-filter-repo"
        exit 1
    }
fi

echo "Removing secrets from git history..."

# Create replacement file
cat > /tmp/replacements.txt << 'EOF'
885193e06bfcfbff6348f1b9caf486a18c2b927e66382223d7c1cafa9858bb72==REDACTED_PRIVATE_KEY
11dfc0d86c9e4451b6e8cc57704dc772==REDACTED_INFURA_KEY
EOF

# Remove secrets from all commits
git filter-repo --replace-text /tmp/replacements.txt --force

# Clean up
rm /tmp/replacements.txt

echo ""
echo "✅ Secrets removed from git history!"
echo ""
echo "⚠️  Next steps:"
echo "1. Review the changes: git log"
echo "2. Force push to remote: git push origin --force --all"
echo "3. ROTATE ALL EXPOSED CREDENTIALS immediately!"
echo ""
echo "⚠️  IMPORTANT: Coordinate with your team before force pushing!"

