# workspace-default detached template files patch

This removes the requirement that `/home/user` must be a Git repository.

TenderHeart may now copy the workspace-default working files into the sandbox
without leaving `.git`, branches, commits, or remotes behind.

Apply:

```bash
bash ./apply-patch.sh workspace-default-detached-template-files-patch.zip
node apply-detached-template-files.mjs
node verify-detached-template-files.mjs
chmod +x setup.sh
```

Commit and push this change before applying the Project TenderHeart patch.
