# Reference

Deeper detail than the README needs - full field lists, both entitySelector patterns, token scopes, and
an engineering-level comparison of the two tiers. Read the README first; come here when you want the
details behind it.

## entitySelector patterns

**Crawl** (`crawl-argocd-notifications/argocd-notifications-cm.yaml`) - targets `CLOUD_APPLICATION` via a
cluster relationship:
```
type(CLOUD_APPLICATION),namespaceName(<namespace>),toRelationships.isClusterOfCa(type(KUBERNETES_CLUSTER),entityName("<cluster-name>"))
```

**Walk** (`walk-cicd-events-api/emit-deployment-event.sh`) - targets `SERVICE` via a namespace
relationship:
```
type(SERVICE),toRelationship.isNamespaceOfService(type(CLOUD_APPLICATION_NAMESPACE),namespaceName("<namespace>"))
```

Both are real, syntax-checked Dynatrace entity selectors (`toRelationships` on crawl's `CLOUD_APPLICATION`
form, `toRelationship` singular on walk's `SERVICE` form - that's not a typo, the two relationship
functions are named differently in the entity model). If you adapt either one, keep the relationship
function name exactly as shown - getting it wrong fails silently: the event still ingests successfully,
it just never resolves to an entity, so nothing shows up on any problem card and there's no error to
notice.

## ArgoCD Notifications Controller field reference

The `template.dynatrace-deploy-event` body in crawl's ConfigMap uses the ArgoCD Notifications Controller's
own Go-template context:

| Field | Value |
|---|---|
| `{{.app.metadata.name}}` | the Application's name |
| `{{.app.status.sync.revision}}` | the git revision just synced |
| `{{.app.spec.destination.namespace}}` | the target namespace |
| `{{.app.status.operationState.phase}}` | `Succeeded` / `Error` / `Failed` / ... (used in the trigger conditions) |

These are standard ArgoCD Notifications Controller template fields - verify them against your installed
ArgoCD version if you're on something unusual; they've been stable across recent releases.

## Token scopes

| Use | Scope |
|---|---|
| Crawl's webhook (`Authorization: Api-Token $dynatrace-api-token`) | `events.ingest` only |
| Walk's script (`DT_API_TOKEN`) | `events.ingest` only |

Neither tier needs anything beyond `events.ingest` - no OAuth client, no AppEngine/workflow-execution
scopes, no Credential Vault. That's deliberate: this pattern works with the plain classic API token your
team probably already issues for other integrations.

## Engineering comparison

| | Crawl: ArgoCD Notifications | Walk: CI/CD + Events API |
|---|---|---|
| Trigger | ArgoCD sync phase change | Your existing deploy pipeline |
| Where the event is built | ArgoCD Notifications Controller template | One script/step in your pipeline |
| Entity targeted | `CLOUD_APPLICATION` (cluster relationship) | `SERVICE` (namespace relationship) |
| Correlation reliability | Non-deterministic in busy namespaces | Reliable in our testing |
| Pipeline changes required | None | One step |
| External dependency | ArgoCD Notifications Controller (already in most ArgoCD installs) | Whatever already runs your deploy pipeline |

## A note on inverted architectures

If you ever build this the other way around - something *other* than your CI/CD pipeline initiates the
deploy (for example, a scheduled automation that triggers a deployment pipeline remotely rather than
running inside it) - you lose direct access to the resulting commit SHA, because:

- A pipeline dispatch (e.g. GitHub Actions' `workflow_dispatch`) doesn't return a run ID.
- A run's own `head_sha` metadata is resolved from the ref *before* that run's own commit+push happens,
  so it still doesn't identify the commit the run itself produces.

The fix in that situation: poll your git host's "latest commit on this branch" endpoint before and after
dispatching, and diff the SHA, timeboxed to however long your deploy step normally takes. Not needed for
either tier here - both run *inside* your existing pipeline, which already knows its own SHA natively -
but worth knowing if you adapt this into a different shape.
