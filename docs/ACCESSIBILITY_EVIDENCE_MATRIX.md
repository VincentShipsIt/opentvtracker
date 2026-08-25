# Accessibility evidence matrix

OpenTV keeps a deterministic simulator evidence matrix for seven primary flows.
The matrix is diagnostic evidence for accessibility acceptance; it does not
replace the human/device gates listed below.

## Matrix contract

The `Accessibility Evidence` workflow runs manually through
`workflow_dispatch`. Each dispatch runs all 14 UI cases on both supported
device classes, for 28 cells total:

The generic required iOS workflow skips this evidence-only test class. Its
30-minute watchdog remains reserved for the regular unit and UI regression
suites; the dedicated workflow owns the slower two-device matrix, retained
attachments, and exact manifest validation.

| Flow | Default Dynamic Type key action | AX5 key action |
| --- | --- | --- |
| First run | Continue on the partner-introduction step | Continue on the partner-introduction step |
| Today | Mark next watched | Mark next watched |
| Discover/search | Seeded result's `discover.search-result.ui-test-show.mark-watched` action | Seeded result's `discover.search-result.ui-test-show.mark-watched` action |
| Shared | Manage private sharing | Manage private sharing |
| Library | Horizontally revealed `library.shelf.paused` filter | Horizontally revealed `library.shelf.paused` filter |
| Media details | Primary tracking action | Primary tracking action |
| Discovery assistant | Enabled `Find picks` on phone; submitted suggestion plus response on iPad | Enabled `Find picks` on phone; submitted full-page wrapped suggestion plus response on iPad |

The device jobs use the newest installed iOS runtime, select an existing
approved simulator when possible, and otherwise create one. The small-iPhone
preference order starts with iPhone SE (3rd generation) and the mini classes;
the iPad preference order starts with iPad mini. A job fails rather than
silently substituting an unapproved large-phone or unsupported device class.

Both Dynamic Type modes are launch arguments, including the default category,
so a simulator's mutable text-size preference cannot change the matrix. Every
case asserts that its key action exists, is hittable, is fully inside the app
viewport, and does not overlap any interactive navigation bar, toolbar, or
floating tab bar.

The assistant uses the production composer and `Find picks` action on the small
phone. On iPad, where the assistant is a popover and simulator keyboard focus is
not deterministic, the case horizontally reveals the production “A tense
sci-fi series” suggestion, requires its whole frame to clear the shelf viewport,
submits it through the same assistant engine, and then requires the real success
or no-exact-match response summary. AX suggestions wrap to one full shelf page.
Accessibility text sizes use the large sheet detent immediately. At every text
size, submitting a request selects the large detent, anchors the result after
the sheet relayout, and requests VoiceOver focus on its summary so the response
does not remain behind the composer.

## Evidence

Each case always retains two named attachments in its `.xcresult`:

- `<flow>-<default|ax5>-screenshot`
- `<flow>-<default|ax5>-accessibility-hierarchy`

The hierarchy attachment includes the simulator name, Dynamic Type mode, and
the app's semantic accessibility tree. The workflow exports the attachment
manifest and compares the exact, unique 14 screenshot names and 14 hierarchy
names against all seven flows in both modes. Missing, extra, or duplicated
evidence fails the device job. Both result bundles are uploaded for 14 days even
when the test command fails.

Generated `.xcresult` bundles are ignored by Git. Export attachments only under
`/tmp` or the ignored `artifacts/` directory, and never commit either result
bundles or exports. Download the two workflow artifacts when reviewing a run,
or inspect a local bundle with:

```bash
xcrun xcresulttool export attachments \
  --path /path/to/AccessibilityEvidence.xcresult \
  --output-path /tmp/opentv-accessibility-evidence
```

For a focused local run, use a supported small iPhone or iPad UDID:

```bash
xcodebuild test \
  -project OpenTVTracker.xcodeproj \
  -scheme OpenTVTracker \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -resultBundlePath /tmp/AccessibilityEvidence.xcresult \
  -only-testing:OpenTVTrackerUITests/AccessibilityEvidenceUITests \
  CODE_SIGNING_ALLOWED=NO
```

## Human/device gates that remain open

This matrix does **not** close issue #61 or issue #54. Release acceptance still
requires human verification on supported physical devices for:

- runtime VoiceOver order and announcements;
- on a supported small iPhone with VoiceOver enabled, submitting a discovery
  assistant request moves spoken focus to `assistant.response-summary` and
  announces the submitted result meaningfully;
- WCAG contrast in real appearance and display conditions;
- Reduce Transparency and Increase Contrast;
- Reduce Motion behavior; and
- touch-target and remaining Dynamic Type acceptance outside these primary
  deterministic flows.

File a bounded product bug for any failed matrix cell. Do not weaken a selector,
frame assertion, device class, or evidence-count requirement to make a run pass.
