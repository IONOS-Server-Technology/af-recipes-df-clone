## What

<!-- Describe what this PR changes and why. -->

## Testing

<!-- How was this tested? -->

## Checklist

- [ ] If logos changed: `recipe_version` bumped in the affected recipe's `metadata.yaml`
      (required — recipe-pipeline will fail without it due to immutable cache headers)
- [ ] Live VM tests run if needed: `test-recipes-live.yaml` only triggers on `feature/IF-*`
      branches, not on PRs — run it manually or via that branch pattern before merging
      if you changed recipe logic, not just metadata
