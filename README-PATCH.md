# Fix detached workspace setup guard

The Project TenderHeart detached-template workflow intentionally copies files
to `/home/user` without `.git`.

The current workspace-default `setup.sh` still contains:

```bash
[ -d "$WORKSPACE_ROOT/.git" ] ||
  die "setup.sh requires TenderHeart to clone the workspace repository first"
```

That makes every new detached sandbox exit with status 1.

Apply and push this patch before creating another workspace:

```bash
bash ./apply-patch.sh workspace-default-fix-detached-setup-guard.zip
node apply-fix-detached-setup-guard.mjs
node verify-fix-detached-setup-guard.mjs
chmod +x setup.sh

git add setup.sh
git commit -m "Allow setup without Git metadata"
git push origin main
```
