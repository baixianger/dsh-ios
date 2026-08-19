# XcodeGen project.yml and encryption

`project.yml` is the source of truth. Regenerate `.xcodeproj`; never hand-edit
generated project files. For generated plists use target `info.properties`, or
for `GENERATE_INFOPLIST_FILE: YES` use `INFOPLIST_KEY_*` settings; edit only
the real `INFOPLIST_FILE` when it is hand-managed.

Set export compliance per target in the owning source: either
`ITSAppUsesNonExemptEncryption: false` in `info.properties`, or
`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO` for generated plists. False
is valid only after auditing dependencies: no custom/bundled cryptography, or
only Apple-provided encryption such as TLS. For non-exempt encryption, obtain
Apple's legally correct compliance answer/code—never guess to silence Connect.

Regenerate, inspect `xcodebuild -showBuildSettings`, build Release, inspect
every app/extension Info.plist, then read the ASC build's processed
`usesNonExemptEncryption`. For upgrades compare installed Apple templates with
XcodeGen presets and consult [Apple's build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference) and [Xcode release notes](https://developer.apple.com/documentation/xcode-release-notes).
