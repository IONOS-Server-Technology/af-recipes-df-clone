# Logo storage buckets

Recipe logos are served as static files from IONOS Object Storage (S3-compatible,
Ceph RGW). Git is the source of truth — the `logo.svg` in each recipe directory is
the canonical artifact; the bucket holds a *derived* copy that the
[`recipe-pipeline.yaml`](../.github/workflows/recipe-pipeline.yaml) `sync-logos`
job uploads on PR and on merge. See RFC-001 §4.6 for the schema-level spec; this
document is the operational reference for the buckets themselves (recreation,
credential rotation, debugging).

> There is **no CDN** in front of these buckets in v1. Logos are served directly
> from the S3 endpoint over IONOS' managed wildcard TLS cert
> (`*.s3.eu-central-3.ionoscloud.com`). A CDN + custom domain
> (`images.af.ionos.com`) was evaluated and deferred to v2 — see IF-712 for the
> rationale. Versioned paths keep that migration painless: only the base URL in
> `metadata.yaml` would change.

## Buckets

| Environment | Bucket | Region | Endpoint |
|---|---|---|---|
| Production | `appfactory` | `eu-central-3` | `https://s3.eu-central-3.ionoscloud.com` |
| PR preview | `appfactory-dev` | `eu-central-3` | `https://s3.eu-central-3.ionoscloud.com` |

**Public URL pattern:**

```
https://<bucket>.s3.eu-central-3.ionoscloud.com/recipes/<id>/<recipe_version>/logo.svg
```

The base URL (bucket hostname) is replaced at serve time by af-api's `AF_LOGO_BASE_URL` environment variable — only the versioned recipe path is stored in `metadata.yaml`.

PR builds upload to `appfactory-dev` only. A merge to `main` uploads to **both**
`appfactory` (prod) and `appfactory-dev` (keeps dev in sync).

## Object layout & headers

```
s3://<bucket>/recipes/<recipe-id>/<recipe_version>/logo.svg
```

- **SVG only** — PNG/WEBP are rejected by both the `af-validate` URL pattern and
  the `sync-logos` upload step's MIME map.
- Paths are **versioned by `recipe_version`**. Every uploaded object carries:

  ```
  Cache-Control: public, max-age=31536000, immutable
  Content-Type:  image/svg+xml
  ```

  `immutable` is safe *only* because the path is versioned: any logo content
  change requires a `recipe_version` bump, which the `sync-logos` job enforces
  (`Enforce recipe_version bump when logo changes` step). Versioned path +
  immutable cache ⇒ consumers never see a stale logo, and there is no need for a
  cache-purge API (which IONOS Object Storage does not expose anyway).

## Credentials

The upload runs as the **if-bot Ceph S3 user**:

```
arn:aws:iam:::user/32938011:fca71ff2-ea07-46b3-8f02-2c12a9bda002
```

Credentials live in Vault at **`imagefactory/data/ci/devel/s3`** as
`S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY`, fetched in CI by the
`IONOS-Server-Technology/if-ci-actions/.github/actions/get-secrets` step.

That user is scoped to `if-image-storage-ceph` by default, so **without explicit
principal grants on the appfactory buckets the workflow gets `AccessDenied (403)`
on `PutObject`** — hence the `IFBot*` statements in the bucket policy below.

### Rotating credentials

The key is the shared if-bot Ceph user, not appfactory-specific. To rotate, issue
a new access key for that Ceph user and update the Vault secret at
`imagefactory/data/ci/devel/s3`. No bucket-policy change is needed unless the
**principal ARN** changes (it shouldn't for a key rotation).

## Bucket policy

Identical on both buckets — replace `appfactory` ↔ `appfactory-dev`. Public read is
scoped to `/recipes/*`; the if-bot principal gets read-everywhere (for debugging)
and write on the whole bucket.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadRecipes",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::appfactory/recipes/*"
    },
    {
      "Sid": "IFBotReadEverywhere",
      "Effect": "Allow",
      "Principal": {
        "AWS": ["arn:aws:iam:::user/32938011:fca71ff2-ea07-46b3-8f02-2c12a9bda002"]
      },
      "Action": ["s3:GetBucketLocation", "s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::appfactory",
        "arn:aws:s3:::appfactory/*"
      ]
    },
    {
      "Sid": "IFBotWrite",
      "Effect": "Allow",
      "Principal": {
        "AWS": ["arn:aws:iam:::user/32938011:fca71ff2-ea07-46b3-8f02-2c12a9bda002"]
      },
      "Action": ["s3:PutObject", "s3:DeleteObject", "s3:GetObjectTagging"],
      "Resource": [
        "arn:aws:s3:::appfactory",
        "arn:aws:s3:::appfactory/*"
      ]
    }
  ]
}
```

> **No IP restriction.** We considered mirroring the `if-image-storage-ceph`
> policy's `aws:SourceIp` allowlist (IF runner subnets) but dropped it — the
> catalogue is non-sensitive and customer-facing.

## CORS

Identical on both buckets. Not strictly required for `<img src>` rendering, but
kept per RFC-001 §4.6 acceptance criteria (cross-origin `fetch()` of a logo).

```json
[
  {
    "AllowedOrigins": ["*"],
    "AllowedMethods": ["GET", "HEAD"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 86400
  }
]
```

## Recreating a bucket from scratch

1. Create the bucket — name `appfactory` (or `appfactory-dev`), region
   `eu-central-3`, Object Lock off.
2. Apply the bucket policy above (substitute the bucket name in all three
   `Resource` blocks).
3. Apply the CORS rule:

   ```bash
   aws s3api put-bucket-cors --bucket appfactory \
     --endpoint-url https://s3.eu-central-3.ionoscloud.com \
     --cors-configuration file://cors.json
   ```

4. Re-run the `recipe-pipeline.yaml` workflow on `main` (e.g. an empty push or a
   manual re-run) so `sync-logos` re-uploads every logo with the correct headers.

> Unlike the IONOS CDN POC (see IF-712), **bucket name does not need to equal a
> domain** here — that quirk only applies when a CDN forwards the `Host` header to
> the origin. Direct S3 access uses the standard `<bucket>.s3.<region>...` virtual
> host, so plain bucket names are fine.

## Verification

```bash
curl -I https://appfactory.s3.eu-central-3.ionoscloud.com/recipes/n8n/1.1.0/logo.svg
# Expect: 200, valid TLS,
#   Cache-Control: public, max-age=31536000, immutable
#   content-type: image/svg+xml
```

The `recipe-pipeline.yaml` workflow runs this reachability check (HEAD against
every active bucket) for every declared `logo_url` on each PR (dev) and
merge-to-main (both buckets).
