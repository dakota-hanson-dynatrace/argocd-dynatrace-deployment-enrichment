# Troubleshooting

## Nothing is showing up on the problem card

**Most common cause: timing.** `CUSTOM_DEPLOYMENT` is a point-in-time event with a 15-minute default
correlation window (`dt.davis.timeout`). Davis only attaches it to a problem that opens (or, for a fix
event, closes) within that window. If your deploy happens long before or after the actual anomaly, there's
nothing to correlate to. For a demo/sandbox cadence, keep the gap between "deploy" and "observable effect"
well under 15 minutes.

**Second most common cause: entitySelector resolves to nothing.** This fails silently - the event ingests
successfully (you'll see a 2xx from the Events API), it just never attaches to an entity, so it can't show
up on any problem card and there's no error to notice. Confirm the event actually resolved to an entity
before assuming correlation itself is broken:

```
fetch events, from:now()-1h
| filter event.type == "CUSTOM_DEPLOYMENT"
| fields timestamp, event.name, affected_entity_ids, affected_entity_types
```

If `affected_entity_ids` is empty, the selector didn't match anything - check the namespace/cluster name
placeholders are substituted correctly, and double-check the relationship function name (see
[reference.md](reference.md) - crawl and walk use differently-named relationship functions, not
interchangeable).

## My markdown links aren't rendering on the problem card

`properties['event.description']` is the field Davis renders as markdown under the event's title - any
other property name is stored but shown as plain data, not rendered. Confirm the description text is
actually landing in that exact key, and that your markdown is `[text](url)` form (standard markdown link
syntax, not HTML).

## Crawl's event lands inconsistently

This is the documented limitation, not a bug to chase: `CLOUD_APPLICATION` targeting via a cluster
relationship doesn't reliably resolve to the right entity when multiple apps in the namespace sync around
the same time. If you're seeing this, it's the expected signal to move to walk, not something to debug
further on crawl.

## A note on inverted architectures (commit-SHA lookup)

If something other than your own CI/CD pipeline initiates the deploy (see
[reference.md](reference.md#a-note-on-inverted-architectures)), you lose direct access to the resulting
commit SHA and have to poll+diff for it instead of reading it natively. Not relevant to either tier as
shipped here, but worth knowing if you restructure this pattern.
