---
name: apple-app-release
description: End-to-end Apple app release workflow. Use for XcodeGen project.yml, local personal/company release profiles, Fastlane, App Store Connect registration, TestFlight, screenshots, encryption export compliance, and review submission.
---

# Apple app release

One profile, one release boundary: select the owner/team identity before any
project or Apple-side change. This avoids signing a project with one identity
and publishing it with another.

## Start here

1. List local profiles in `profiles/`. If none exists, ask the user to create
   one from `references/profiles.md`; if several exist, require the user to
   choose. There is no implicit default.
2. Verify the chosen profile against the exact bundle ID and generated
   `DEVELOPMENT_TEAM` for every app/extension target.
3. Load only the relevant module:

| Task | Reference |
|---|---|
| `project.yml`, Info.plist, signing, versions, encryption, Xcode/XcodeGen upgrades | `references/project-yml.md` |
| Register app, Fastlane, metadata, TestFlight, Connect or review submission | `references/connect.md` |
| Generate, replace, or verify App Store screenshots | `references/media.md` |

Profiles are local configuration; repositories hold product facts. Never put
keys, passwords, personal contacts, profile contents, or private data in an
app repository or a factory skill.
