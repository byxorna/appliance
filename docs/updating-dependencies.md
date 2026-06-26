# Keeping Dependencies Up to Date

Three categories of pinned dependencies need periodic updates.

## Dependency categories

### Yocto upstream layers

Pinned by `commit:` in `kas/features/common.yaml`. Each tracks a branch (typically `scarthgap`) of its upstream repo. Update within the tracked branch only. Moving to a different Yocto release is a major migration, not a dependency bump.

### BSP and infrastructure layers

Pinned by `commit:` in `kas/machines/*.yaml`. The same commit often appears in multiple machine configs. When updating a shared layer, update every file that references it.

### Container application versions

Pinned as `ARG` values in `containers/*/Dockerfile`. These are the safest to update. Container images rebuild independently and don't affect the rootfs build.

## Automated update discovery

Updatecli manifests in `updatecli/` declaratively track all three dependency categories. Updatecli runs in a container, so no local installation is needed.

### Checking for updates

```bash
make check-updates
```

Runs `updatecli diff` against all manifests. Reports which pins are outdated and what the latest values are. Read-only, modifies nothing.

Container app manifests query GitHub releases, which requires a token even for public repos. Pass a GitHub PAT (no permissions needed for public repos):

```bash
make check-updates UPDATECLI_GITHUB_TOKEN=ghp_...
```

Layer commit tracking uses `git ls-remote` and needs no token.

### Applying updates

```bash
make apply-updates
```

Runs `updatecli apply`, which modifies files in place. Review the diff with `git diff` before committing.

### After updating

Parse-check at least one variant per machine family:

```bash
make VARIANT=reterminal-hifi check
make VARIANT=raspberrypi3-64-base check
```

Build at least one variant to verify the full build succeeds.

## Manual update process

### Updating a layer pin

1. Check the upstream branch for new commits:

```bash
git ls-remote <UPSTREAM_URL> <BRANCH>
```

2. Update the `commit:` value in the relevant kas YAML file(s). For BSP layers shared across machines, update all files that reference the layer:

```bash
grep -rl '<LAYER_NAME>' kas/ | xargs -I{} \
  sed -i '' 's/commit: OLD_SHA/commit: NEW_SHA/' {}
```

3. Parse-check and build as described above.

### Updating a container app version

1. Check the upstream project for new releases.
2. Update the `ARG` line in the relevant Dockerfile.
3. Rebuild the container (`make build-container-<name>`).
4. Test on a device or in a local podman run.
