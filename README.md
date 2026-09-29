# CI/CD Bootstrap: GitHub Actions + AWS OIDC (no stored keys)

Sets up everything needed for **keyless, least-privilege deployments** from GitHub Actions to AWS:

| Resource | Why |
|----------|-----|
| **IAM OIDC provider** for `token.actions.githubusercontent.com` | GitHub proves its identity to AWS with a signed token |
| **IAM role** `github-actions-visitor-counter` | Only assumable by `morcosfady/aws-serverless-visitor-counter` (main branch or PRs), 1-hour sessions |
| **Scoped permissions** | Can only manage the visitor counter's own Lambda, API, table, log group, and role |
| **S3 state bucket** | Versioned, encrypted, private shared Terraform state |
| **DynamoDB lock table** | Stops two deploys from changing infrastructure at the same time |

## Why OIDC instead of access keys?

| Access keys in GitHub Secrets | OIDC |
|---|---|
| Long-lived, valid until someone rotates them | Temporary, expire after 1 hour |
| Leak = full access until noticed | Nothing to leak |
| Any workflow can use them | Trust policy limits it to one repo + branch |

## Pipeline (in the visitor counter repo)

```
Pull request -> fmt check -> init -> validate -> plan   (review changes safely)
Push to main -> ... -> plan -> apply -> smoke test the live API
```

## Cost

About $0: OIDC and IAM are free, GitHub Actions is free for public repos, and the state bucket and lock table hold only a few KB.
