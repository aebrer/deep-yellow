---
name: publish-deep-yellow
description: >
  Publish a new release of Deep Yellow to itch.io and GitHub. Use when Drew says
  "let's publish", "release this", "push to itch", or wants to do a full release
  of the deep_yellow project. Handles export, butler push, git tagging, and
  GitHub release creation.
---

# Publish Deep Yellow

Full publish workflow for the Deep Yellow Godot game. All commands run from the project root.

## Prerequisites

- Must be on `master` branch with all changes merged
- Previous version tag exists (workflow auto-increments)
- Butler installed at `/home/drew/.local/bin/butler`
- Godot export presets configured (Linux, Windows Desktop, Web)

## Workflow

### Step 1: Determine version

```bash
cd /home/drew/projects/deep_yellow
git tag --sort=-v:refname | head -1
```

Ask Drew what version to tag (patch, minor, or major bump), or infer from the scope of changes since last tag.

### Step 2: Export all platforms (headless)

```bash
cd /home/drew/projects/deep_yellow
godot --headless --export-release "Linux"
godot --headless --export-release "Windows Desktop"
godot --headless --export-release "Web"
```

### Step 3: Push to itch.io with butler

```bash
VERSION=v0.X.Y  # from step 1
/home/drew/.local/bin/butler push build/linux aebrer/deep-yellow:linux --userversion $VERSION
/home/drew/.local/bin/butler push build/windows aebrer/deep-yellow:windows --userversion $VERSION
/home/drew/.local/bin/butler push build/web aebrer/deep-yellow:html5 --userversion $VERSION
```

### Step 4: Verify uploads

```bash
/home/drew/.local/bin/butler status aebrer/deep-yellow
```

### Step 5: Create tar.gz archives for GitHub release

```bash
cd /home/drew/projects/deep_yellow/build
tar czf deep_yellow_${VERSION}_linux.tar.gz -C linux .
tar czf deep_yellow_${VERSION}_windows.tar.gz -C windows .
tar czf deep_yellow_${VERSION}_web.tar.gz -C web .
```

### Step 6: Create git tag and push

```bash
cd /home/drew/projects/deep_yellow
git tag $VERSION
git push origin $VERSION
```

### Step 7: Create GitHub release

```bash
gh release create $VERSION \
  /home/drew/projects/deep_yellow/build/deep_yellow_${VERSION}_linux.tar.gz \
  /home/drew/projects/deep_yellow/build/deep_yellow_${VERSION}_windows.tar.gz \
  /home/drew/projects/deep_yellow/build/deep_yellow_${VERSION}_web.tar.gz \
  --title "$VERSION — Release Title" \
  --notes "Release notes here"
```

Use a HEREDOC for multi-line release notes. Include a link to the itch.io page:
`[aebrer.itch.io/deep-yellow](https://aebrer.itch.io/deep-yellow)`

### Step 8: itch.io devlog (manual)

Remind Drew that butler can't post devlogs — this step is manual via the itch.io web interface if desired.

## Notes

- Export preset names are case-sensitive: "Linux", "Windows Desktop", "Web"
- Butler uses delta compression — subsequent pushes are fast
- Use absolute paths for `gh release create` asset arguments
- Archives go in `build/` alongside the platform directories
- `gh pr edit` may fail with GraphQL error — use `gh api` directly if needed (see CLAUDE.md)
