# HiClaude Agent Notes

## Release prompt

After any code, documentation, workflow, packaging, or cask change in this repo,
ask the user whether to create a new release before finishing the task.

If the answer is yes, use the existing release flow:

1. Confirm the next semantic version.
2. Update `scripts/Info.plist` if the app version changes.
3. Commit the changes with the repo-local Git identity.
4. Create and push a `vX.Y.Z` tag.
5. Verify the `release` GitHub Actions workflow finishes successfully.
6. Verify the Homebrew tap cask is updated and `brew upgrade --cask hiclaude`
   can see the new version.

Do not assume that pushing `main` updates users. Homebrew users only receive an
update after a new tag/release updates `hayashirafael/homebrew-tap`.
