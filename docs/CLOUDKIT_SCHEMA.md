# CloudKit schema

OpenTV Tracker uses the `iCloud.dev.opentvtracker.app` container for invitation-only partner sharing. Personal tracking remains local and does not require iCloud.

The source-controlled schema is [`CloudKit/OpenTVTracker.ckdb`](../CloudKit/OpenTVTracker.ckdb). It defines only the custom application types:

| Record type | Field | CloudKit type |
| --- | --- | --- |
| `PartnerSpace` | `spaceID` | String |
| `PartnerSpace` | `schemaVersion` | Int(64) |
| `PartnerSpace` | `createdAt` | Date/Time |
| `PartnerSpaceState` | `payload` | Bytes |
| `PartnerSpaceState` | `updatedAt` | Date/Time |
| `PartnerSpaceState` | `schemaVersion` | Int(64) |

CloudKit supplies system fields such as record ID and parent automatically. No public-database grants or query indexes are required: records live in a private custom zone, access is granted through `CKShare`, and synchronization uses record-zone changes and stable record IDs rather than queries.

## Import into Development

1. Open CloudKit Console and select `iCloud.dev.opentvtracker.app`.
2. Confirm the environment at the top is **Development**.
3. Choose **Import Schema…**.
4. Select `CloudKit/OpenTVTracker.ckdb`.
5. Confirm `PartnerSpace` and `PartnerSpaceState` appear under **Schema → Record Types** with the fields listed above.

The command-line equivalent requires a CloudKit management token:

```sh
xcrun cktool import-schema \
  --team-id C76R5DRH64 \
  --container-id iCloud.dev.opentvtracker.app \
  --environment development \
  --file CloudKit/OpenTVTracker.ckdb
```

## Promote to Production

1. While still viewing **Development**, choose **Deploy Schema Changes…**.
2. Review the deployment and confirm both application record types and all six fields are included.
3. Deploy the changes.
4. Switch the environment to **Production** and verify the two record types are present.

CloudKit command-line tools import schemas only into Development. Production promotion is intentionally completed in CloudKit Console. Treat the production schema as additive: removing a deployed record type or field is not a supported migration path.

## Release verification

After promotion, test with two physical devices signed into different iCloud accounts:

1. Create a Together invitation on the owner device.
2. Accept it on the partner device.
3. Change shared progress on each device and confirm the other receives it.
4. Exercise offline retry, decline, leave, revoke, and Apple ID switching.
