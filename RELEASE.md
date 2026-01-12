# Release Process for Gula CLI

## Version Management

The version is managed from a **single source of truth**: the `VERSION` file in the repository root.

```
VERSION              <- Single source of truth (e.g., "0.0.175")
    |
    +-> scripts/global_vars.sh  (reads VERSION at runtime)
    +-> Formula/gula.rb         (updated during release)
```

## How to Release a New Version

### Step 1: Update VERSION file

```bash
# Increment version (e.g., from 0.0.174 to 0.0.175)
echo "0.0.175" > VERSION
```

### Step 2: Commit changes

```bash
git add .
git commit -m "Description of changes

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

### Step 3: Create and push tag

```bash
# Read version from file
NEW_VERSION=$(cat VERSION)

# Create tag and push
git tag "$NEW_VERSION"
git push origin main
git push origin "$NEW_VERSION"
```

### Step 4: Update Formula with new SHA256

```bash
# Get SHA256 of new release tarball
NEW_VERSION=$(cat VERSION)
SHA256=$(curl -sL "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/${NEW_VERSION}.tar.gz" | shasum -a 256 | cut -d' ' -f1)

echo "New SHA256: $SHA256"

# Update Formula/gula.rb with new version and SHA256
# Replace the url and sha256 lines with:
#   url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/${NEW_VERSION}.tar.gz"
#   sha256 "${SHA256}"
```

### Step 5: Commit Formula update

```bash
git add Formula/gula.rb
git commit -m "Update sha256 for v${NEW_VERSION}"
git push origin main
```

## Quick Release (All Steps Combined)

```bash
# 1. Set new version
NEW_VERSION="0.0.175"  # Change this to your new version
echo "$NEW_VERSION" > VERSION

# 2. Commit your changes
git add .
git commit -m "Your commit message

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"

# 3. Tag and push
git tag "$NEW_VERSION"
git push origin main
git push origin "$NEW_VERSION"

# 4. Get SHA256 and update Formula
SHA256=$(curl -sL "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/${NEW_VERSION}.tar.gz" | shasum -a 256 | cut -d' ' -f1)

# 5. Edit Formula/gula.rb - update url version and sha256
# Then:
git add Formula/gula.rb
git commit -m "Update sha256 for v${NEW_VERSION}"
git push origin main
```

## For Claude AI Sessions

When asked to release a new version:

1. **Read current version**: `cat VERSION`
2. **Increment version**: Update VERSION file with new version number
3. **Commit changes**: Include all modified files with descriptive message
4. **Create git tag**: Tag must match VERSION content exactly
5. **Push to remote**: Push both main branch and tag
6. **Update Formula**: Get SHA256 from tarball URL and update Formula/gula.rb
7. **Push Formula update**: Commit and push the sha256 update

Users will receive the update automatically (auto-update runs every hour).
