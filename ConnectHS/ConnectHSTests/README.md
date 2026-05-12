# ConnectHSTests

Pure-logic XCTest suites that don't need Supabase, the camera, or UIKit.
Currently:

- `InviteURLTests` — the deep-link / universal-link parser.
- `LatestPostPayloadTests` — App Group payload Codable round-trip.
- `ReactionTypeTests` — emoji + accessibility-key + SQL-enum parity.

## Running

```
xcodebuild test -scheme ConnectHS -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The `ConnectHSTests` Unit Testing Bundle target is wired into `project.pbxproj`
(bundle id `com.connecths.ConnectHS.tests`, host app `ConnectHS`,
`TEST_HOST` + `BUNDLE_LOADER` set so `@testable import ConnectHS` resolves).
Adding new test files is just `Add Files to ConnectHSTests` in Xcode — the
target picks them up via its Sources build phase.

## Why these tests

Spec/CLAUDE.md says "Always build and run tests before claiming a task
is complete," but the project has had no test infrastructure to date.
These three suites are a starter set — they exercise the only pieces of
the codebase that are pure-Swift and side-effect-free, so they're a
guaranteed-green baseline you can extend without first solving the
"how do I mock Supabase" problem.

## What NOT to put here

- Anything that hits Supabase. Use `supabase/tests/*.sql` (rollback-safe
  service-role scripts) for schema/RPC tests.
- Anything that mounts a SwiftUI view. UI tests live in `ConnectHSUITests/`.
- Anything time-sensitive (e.g. quiet-hours math). Those live in the edge
  function tests once we add a Deno test target.
