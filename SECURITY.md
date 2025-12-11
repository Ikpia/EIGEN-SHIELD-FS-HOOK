# Security Notice

## ⚠️ IMPORTANT: Secrets Were Exposed

**Date**: December 11, 2025

**Issue**: Private keys and API keys were accidentally committed to git history in commit `c3d8678`.

**Action Required**:
1. **IMMEDIATELY ROTATE ALL EXPOSED CREDENTIALS**:
   - Private Key: `885193e06bfcfbff6348f1b9caf486a18c2b927e66382223d7c1cafa9858bb72`
   - Infura API Key: `11dfc0d86c9e4451b6e8cc57704dc772`
   - Any wallets associated with these keys

2. **Git History Cleaned**: The secrets have been removed from future commits, but they remain in git history.

3. **To Completely Remove from GitHub**:
   ```bash
   # Install git-filter-repo (recommended)
   pip install git-filter-repo
   
   # Remove secrets from all history
   git filter-repo --path deploy-base-sepolia.sh --invert-paths
   git filter-repo --replace-text <(echo "885193e06bfcfbff6348f1b9caf486a18c2b927e66382223d7c1cafa9858bb72==REDACTED")
   git filter-repo --replace-text <(echo "11dfc0d86c9e4451b6e8cc57704dc772==REDACTED")
   
   # Force push (WARNING: This rewrites history)
   git push origin --force --all
   ```

## Current Security Status

✅ **Current State**:
- `.env` file is properly ignored (in `.gitignore`)
- `.env.example` contains only placeholders
- `deploy-base-sepolia.sh` no longer contains hardcoded secrets
- Secrets are loaded from `.env` file only

## Best Practices Going Forward

1. **Never commit secrets**:
   - Private keys
   - API keys
   - Passwords
   - Seed phrases

2. **Use environment variables**:
   - Store secrets in `.env` (gitignored)
   - Use `.env.example` as template
   - Load from environment in scripts

3. **Pre-commit hooks** (recommended):
   ```bash
   # Install pre-commit
   pip install pre-commit
   
   # Add to .pre-commit-config.yaml
   ```

4. **GitHub Secrets** (for CI/CD):
   - Use GitHub Actions secrets
   - Never hardcode in workflows

## If Secrets Are Exposed

1. **Immediately rotate** all exposed credentials
2. **Check for unauthorized access** to accounts/services
3. **Clean git history** using git-filter-repo
4. **Force push** to remove from remote (coordinate with team)
5. **Monitor** accounts for suspicious activity

