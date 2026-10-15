#!/usr/bin/env bash
# Posts a Dynatrace CUSTOM_DEPLOYMENT event targeted directly at the SERVICE entity,
# via a namespace relationship - this is the fix for crawl's known limitation
# (CLOUD_APPLICATION targeting via a cluster relationship doesn't always land the
# event on the right entity when several apps deploy concurrently). This one
# reliably correlates.
#
# CI-agnostic: this is one `curl` call, so it drops into any CI/CD system (GitHub
# Actions, GitLab CI, Jenkins, CircleCI, ...) as a single pipeline step - no new
# tooling, no Dynatrace-side automation needed. Your CI system already knows its
# own commit SHA, so there's nothing to look up or poll for.
#
# Usage: all inputs are env vars so this drops into any pipeline unchanged.
#
#   DT_TENANT        your-tenant (no scheme, no trailing slash - just the id)
#   DT_API_TOKEN      Dynatrace API token, events.ingest scope only
#   APP               the deployed app/service name, e.g. "checkout-service"
#   NAMESPACE         the k8s namespace Dynatrace already sees this service in
#   COMMIT_SHA        short or full commit sha for this deploy
#   COMMIT_MESSAGE    commit message / subject line for this deploy
#   GIT_URL           link to the commit (optional but recommended)
#   ARGOCD_URL        link to the ArgoCD Application, or your CD tool's UI (optional)
#   INGRESS_URL       public/internal URL for the app itself (optional)
#   OWNER             owning team (optional)
#   STAGE             e.g. "prod", "staging" (optional)
#   PROJECT           your project/product name (optional)
#
# Example (plain shell):
#   DT_TENANT=abc12345 DT_API_TOKEN=dt0c01.xxx APP=checkout-service \
#   NAMESPACE=storefront COMMIT_SHA=$(git rev-parse --short HEAD) \
#   COMMIT_MESSAGE="$(git log -1 --format=%s)" \
#   ./emit-deployment-event.sh
#
# Example (GitHub Actions step):
#   - name: Notify Dynatrace of deployment
#     env:
#       DT_TENANT: ${{ vars.DT_TENANT }}
#       DT_API_TOKEN: ${{ secrets.DT_API_TOKEN }}
#       APP: checkout-service
#       NAMESPACE: storefront
#       COMMIT_SHA: ${{ github.sha }}
#       COMMIT_MESSAGE: ${{ github.event.head_commit.message }}
#       GIT_URL: https://github.com/${{ github.repository }}/commit/${{ github.sha }}
#     run: ./walk-cicd-events-api/emit-deployment-event.sh

set -euo pipefail

: "${DT_TENANT:?set DT_TENANT}"
: "${DT_API_TOKEN:?set DT_API_TOKEN}"
: "${APP:?set APP}"
: "${NAMESPACE:?set NAMESPACE}"
: "${COMMIT_SHA:?set COMMIT_SHA}"
: "${COMMIT_MESSAGE:?set COMMIT_MESSAGE}"

GIT_URL="${GIT_URL:-}"
ARGOCD_URL="${ARGOCD_URL:-}"
INGRESS_URL="${INGRESS_URL:-}"
OWNER="${OWNER:-}"
STAGE="${STAGE:-}"
PROJECT="${PROJECT:-}"
SHORT_SHA="${COMMIT_SHA:0:7}"
ENTITY_SELECTOR="type(SERVICE),toRelationship.isNamespaceOfService(type(CLOUD_APPLICATION_NAMESPACE),namespaceName(\"${NAMESPACE}\"))"

# Built with jq, not string interpolation into a JSON template - commit messages
# routinely contain quotes/backslashes/newlines that would otherwise produce
# invalid JSON. jq ships on virtually every CI runner (incl. GitHub-hosted ones).
BODY=$(jq -n \
  --arg app "$APP" --arg sha "$SHORT_SHA" --arg selector "$ENTITY_SELECTOR" \
  --arg ingress "$INGRESS_URL" --arg argocd "$ARGOCD_URL" --arg git "$GIT_URL" \
  --arg msg "$COMMIT_MESSAGE" --arg owner "$OWNER" --arg stage "$STAGE" --arg project "$PROJECT" \
  '{
    eventType: "CUSTOM_DEPLOYMENT",
    title: ("ArgoCD Sync: " + $app + " (git#" + $sha + ")"),
    entitySelector: $selector,
    properties: {
      source: "argocd",
      "event.description": ("Deployment from [" + $app + "](" + $ingress + ") by [ArgoCD](" + $argocd + ") from [commit](" + $git + "): \"" + $msg + "\""),
      app: $app,
      commit: $sha,
      gitUrl: $git,
      argocdUrl: $argocd,
      ingressUrl: $ingress,
      owner: $owner,
      stage: $stage,
      project: $project
    }
  }')

curl -sf -X POST "https://${DT_TENANT}.live.dynatrace.com/api/v2/events/ingest" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${BODY}"
