# Contributing

## Getting Started

1. Enable local git hooks: `git config core.hooksPath .githooks`
2. Create a feature branch from `main`: `git checkout -b feat/your-feature`
3. Make changes in the `terraform/` directory
4. Run `terraform fmt -recursive terraform/` before committing
5. Commit using conventional commit format (see below)
6. Open a pull request to `main`

## Conventional Commits

This repo uses [Conventional Commits](https://www.conventionalcommits.org/) to automate version bumping and changelog generation:

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

Header must be 120 characters or fewer. Use the body for detail.

### Types and Their Semver Impact

| Type       | Semver Bump       | When to Use                            | Example                                    |
| ---------- | ----------------- | -------------------------------------- | ------------------------------------------ |
| `fix`      | **Patch** (0.0.x) | Bug fixes                              | `fix(iam): correct policy resource ARN`    |
| `feat`     | **Minor** (0.x.0) | New functionality                      | `feat(s3): add logging bucket`             |
| `perf`     | **Patch** (0.0.x) | Performance improvements               | `perf(lambda): reduce cold start time`     |
| `refactor` | **Patch** (0.0.x) | Restructuring without behaviour change | `refactor(modules): split into submodules` |
| `docs`     | No release        | Documentation only                     | `docs: update README`                      |
| `chore`    | No release        | Maintenance, CI changes                | `chore: update trivy action version`       |

### Breaking Changes (Major Bump)

Add `BREAKING CHANGE:` in the commit footer:

```
feat(vpc): replace subnet configuration

BREAKING CHANGE: `subnet_ids` replaced with `subnet_config` object.
```

### Examples

**Patch release (v1.0.0 → v1.0.1):**

```
fix(security-group): allow egress to NTP servers
```

**Minor release (v1.0.1 → v1.1.0):**

```
feat(rds): add Aurora PostgreSQL cluster
```

**Major release (v1.1.0 → v2.0.0):**

```
feat(networking): restructure VPC module

BREAKING CHANGE: The `vpc_cidr` variable is now required.
All existing deployments must add this variable to their tfvars.
```

## Pull Requests

- Target `main` branch
- All CI checks must pass (fmt, tflint, trufflehog, trivy)
- PR title should follow conventional commit format

## Release Process

Releases happen automatically when PRs merge to `main`:

1. Analyses commits since the last tag
2. Determines version bump from conventional commit prefixes
3. Creates a git tag and GitHub Release with changelog
