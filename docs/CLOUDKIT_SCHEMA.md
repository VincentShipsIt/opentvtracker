# CloudKit schema

The official OpenTV Tracker app uses the `iCloud.dev.opentvtracker.app` container for invitation-only partner sharing. Personal tracking remains local and does not require iCloud. Forks must use their own CloudKit container, Team ID, bundle entitlements, and provisioning profile throughout this guide.

The source-controlled schema is [`CloudKit/OpenTVTracker.ckdb`](../CloudKit/OpenTVTracker.ckdb). It defines only the custom application types:

| Record type | Field | CloudKit type |
| --- | --- | --- |
| `PartnerSpace` | `spaceID` | String |
| `PartnerSpace` | `schemaVersion` | Int(64) |
| `PartnerSpace` | `createdAt` | Date/Time |
| `PartnerSpaceState` | `payload` | Bytes |
| `PartnerSpaceState` | `updatedAt` | Date/Time |
| `PartnerSpaceState` | `schemaVersion` | Int(64) |

CloudKit supplies system fields such as record ID and parent automatically. It also generates the `cloudkit.share` record type only after a Development build successfully saves its first `CKShare`; importing the custom schema alone does not create that type. No public-database grants or query indexes are required: records live in a private custom zone, access is granted through `CKShare`, and synchronization uses record-zone changes and stable record IDs rather than queries.

## Import into Development

1. Open CloudKit Console and select `iCloud.dev.opentvtracker.app` for the official app, or the fork's own configured container.
2. Confirm the environment at the top is **Development**.
3. Choose **Import Schema…**.
4. Select `CloudKit/OpenTVTracker.ckdb`.
5. Confirm `PartnerSpace` and `PartnerSpaceState` appear under **Schema → Record Types** with the fields listed above.

The command-line equivalent requires a CloudKit management token. The values below are for the official app; forks must replace both identifiers:

```sh
xcrun cktool import-schema \
  --team-id C76R5DRH64 \
  --container-id iCloud.dev.opentvtracker.app \
  --environment development \
  --file CloudKit/OpenTVTracker.ckdb
```

## Promote to Production

1. Install a Development-signed build that uses the target container.
2. With the Console environment still set to **Development**, create a real Together invitation. The successful `CKShare` save seeds CloudKit's generated sharing schema.
3. Refresh **Schema → Record Types** and verify `cloudkit.share` is present alongside `PartnerSpace` and `PartnerSpaceState`. Do not promote the schema until it appears.
4. Choose **Deploy Schema Changes…**.
5. Review the deployment and confirm both application record types, all six custom fields, and the generated `cloudkit.share` changes are included.
6. Deploy the changes.
7. Switch the environment to **Production** and verify all three record types are present.

CloudKit command-line tools import schemas only into Development. Production promotion is intentionally completed in CloudKit Console. Treat the production schema as additive: removing a deployed record type or field is not a supported migration path.

## Release verification

After promotion, test with two physical devices signed into different iCloud accounts:

1. Create a Together invitation on the owner device and confirm no production-schema error is shown.
2. Accept it on the partner device.
3. Change shared progress on each device and confirm the other receives it.
4. Mark a title or episode watched together and confirm the partner receives one notification.
5. Exercise offline retry, denied-then-enabled notification permission, decline, leave, revoke, and Apple ID switching.
