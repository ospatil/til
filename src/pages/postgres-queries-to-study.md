---
layout: ../layouts/GistLayout.astro
tags: [database,postgres]
---

# Postgres queries to study

Getting relations

There are three entities - `contract_requests` , `addresses` and `contract_request_items` 

There is `one-to-many` relationship between `contract_requests` and `contract_request_items`.

There is `one-to-one` relationship between `contract_requests` and `addresses` (`originAddress`)

The following query fetches all the `contractRequests` with `originAddress` and `contractRequestItems` 

```tsx
it.only('print the query', async () => {
  const query = db.query.contractRequests.findMany({
    columns: {
      id: true,
    },
    with: {
      originAddress: true,
      // destinationAddress: true,
      contractRequestItems: true,
    },
  }).toSQL()
  // eslint-disable-next-line no-console
  console.log(query)
})
```

```sql
select
  "contractRequests"."id",
  "contractRequests_originAddress"."data" as "originAddress",
  "contractRequests_contractRequestItems"."data" as "contractRequestItems"
from
  "contract_requests" "contractRequests"
  left join lateral (
    select
      json_build_array(
        "contractRequests_originAddress"."id",
        "contractRequests_originAddress"."line_one",
        "contractRequests_originAddress"."line_two",
        "contractRequests_originAddress"."city",
        "contractRequests_originAddress"."province_state",
        "contractRequests_originAddress"."postal_code_zip",
        "contractRequests_originAddress"."country",
        "contractRequests_originAddress"."created_at",
        "contractRequests_originAddress"."updated_at",
        "contractRequests_originAddress"."created_by",
        "contractRequests_originAddress"."updated_by"
      ) as "data"
    from
      (
        select
          *
        from
          "addresses" "contractRequests_originAddress"
        where
          "contractRequests_originAddress"."id" = "contractRequests"."origin_address_id"
        limit
          $ 1
      ) "contractRequests_originAddress"
  ) "contractRequests_originAddress" on true
  left join lateral (
    select
      coalesce(
        json_agg(
          json_build_array(
            "contractRequests_contractRequestItems"."id",
            "contractRequests_contractRequestItems"."contract_request_id",
            "contractRequests_contractRequestItems"."emo",
            "contractRequests_contractRequestItems"."cfr_cfcu",
            "contractRequests_contractRequestItems"."description",
            "contractRequests_contractRequestItems"."length",
            "contractRequests_contractRequestItems"."width",
            "contractRequests_contractRequestItems"."height",
            "contractRequests_contractRequestItems"."weight",
            "contractRequests_contractRequestItems"."pickup_date",
            "contractRequests_contractRequestItems"."delivery_date",
            "contractRequests_contractRequestItems"."remarks",
            "contractRequests_contractRequestItems"."created_at",
            "contractRequests_contractRequestItems"."updated_at",
            "contractRequests_contractRequestItems"."created_by",
            "contractRequests_contractRequestItems"."updated_by"
          )
        ),
        '[]' :: json
      ) as "data"
    from
      "contract_request_items" "contractRequests_contractRequestItems"
    where
      "contractRequests_contractRequestItems"."contract_request_id" = "contractRequests"."id"
  ) "contractRequests_contractRequestItems" on true
```

Getting latest assigned status for entity

There are three entities - `contract_requests` , `contract_requests_status_history` and `contract_request_statuses` 

There is a `one-to-many` relationship between between `contract_requests` and `contract_requests_status_history` .

The `contract_request_statuses` is a reference table that stores various statuses for the `contract_requests` .

The following query fetches the latest `assigned` status along with  `contract_request` id for a user.

```tsx
export async function getAssignedRequestIdsForUser(userId: string) {
  const assignedStatus = db.select({ id: contractRequestStatuses.id })
    .from(contractRequestStatuses)
    .where(eq(contractRequestStatuses.status, 'assigned')).as('assignedStatus')

  const latestAssigned = db.select({
    contractRequestId: contractRequestStatusHistory.contractRequestId,
    maxUpdatedAt: max(contractRequestStatusHistory.updatedAt).as('maxUpdatedAt'),
  })
    .from(contractRequestStatusHistory)
    .innerJoin(assignedStatus, eq(assignedStatus.id, contractRequestStatusHistory.contractRequestStatusId))
    .groupBy(contractRequestStatusHistory.contractRequestId)
    .as('latestAssigned')

  return db.select({
    id: contractRequestStatusHistory.contractRequestId,
  })
    .from(latestAssigned)
    .innerJoin(contractRequestStatusHistory, and(eq(contractRequestStatusHistory.contractRequestId, latestAssigned.contractRequestId), eq(contractRequestStatusHistory.updatedAt, latestAssigned.maxUpdatedAt)))
    .where(eq(contractRequestStatusHistory.updatedBy, userId))
}
```

The same query can be written as pure Postgres query using DrizzleORM `sql` operator

```tsx
export async function getAssignedRequestIdsForUser(userId: string) {
  return db.execute(sql`
    SELECT rsh.contract_request_id as id
    FROM (
      SELECT contract_request_id, MAX(updated_at) AS max_updated_at
      FROM contract_request_status_history
      WHERE contract_request_status_id = (SELECT id FROM contract_request_statuses WHERE status_name = 'assigned')
      GROUP BY contract_request_id
    ) AS latest_assigned_statuses
    JOIN contract_request_status_history rsh ON rsh.contract_request_id = latest_assigned_statuses.contract_request_id AND rsh.updated_at = latest_assigned_statuses.max_updated_at
    WHERE rsh.updated_by = ${userId}
  `)
}
```

### Explanations

https://poe.com/s/2fCH9Tgzk3VsrxDuXG0d

https://poe.com/s/pQimsWI8alPSYWrft50L

https://poe.com/s/5iBDmcpfvZm7CLXlso5x

https://poe.com/s/TGoZdDXmo7X2qSVbz4B8

https://poe.com/s/NBqUYZMEKmPPdKMFpEZz

https://poe.com/s/pjA8bMKY4FypwPna8zCa

### Explanation for lateral join

[https://claude.ai/chat/076462d0-b1a9-4555-891b-5e6d064df443](https://claude.ai/chat/076462d0-b1a9-4555-891b-5e6d064df443)
