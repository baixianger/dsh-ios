# Profiles and credentials

Profiles are local, non-secret files in `profiles/`. If none exists, create a
named one with owner label, bundle namespace, Team-ID env-variable name and a
private credential-root/env-file location. If multiple exist, ask the user to
choose for this operation. Never infer identity from cwd or an app name.

Each private credential root uses `0700`, with `release.env` and `.p8` files
at `0600`. `release.env` supplies Team ID, ASC key ID/issuer ID/key path and,
if applicable, match Git URL/password. ASC keys come from App Store Connect →
Users and Access → Integrations → Keys; Team ID comes from Apple Developer
membership details. Apple-ID/app-specific-password credentials are only for
Apple-ID-only operations. Never log or commit these values.
