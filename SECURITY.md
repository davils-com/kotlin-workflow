# Security

## Reporting a vulnerability

Report it privately through
[GitHub security advisories](https://github.com/davils-com/kotlin-workflow/security/advisories/new),
not in a public issue. Say which workflow or action is affected and how to reproduce it.

## What is in scope

These workflows run in the repositories that call them, with the permissions and secrets those
repositories grant. In scope is anything that lets a run do more than its caller intended: a
secret that reaches a job which builds untrusted code, a value from an event that is evaluated as
a script, a reference that is not pinned, a gate that can be passed without meeting its rule.

How the workflows guard against these is described in [docs/security.md](docs/topics/Security.md).

## Supported versions

The latest release of the latest major version.
