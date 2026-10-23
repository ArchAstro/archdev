# Public file sharing

`archdev share` publishes static files through ArchDev's normal user login.
No AWS CLI, bucket credentials, Pulumi login, or model provider is required.
The gateway must have public sharing configured; a missing endpoint does not
prove a share was deleted. Report configuration/authentication errors rather
than switching to the repository's internal shared-credential uploader.

## Upload and preview

```sh
"$archdev" --json share upload report.html screenshots/ --dry-run
"$archdev" --json share upload report.html screenshots/ --public
```

Preview validates all inputs and prints their file manifests without logging in
or writing anything remotely. Upload requires explicit `--public`. Non-sensitive
screenshots and recordings used as PR visual evidence do not need separate
upload approval; exclude or redact sensitive data before uploading. Other
content still requires the user's request to publish. `--public` does not
authorize unrelated content. Public publication cannot be undone for copies
others already saved.

Results contain a `shares` array in input order with each share's `id`,
`user_id`, `url`, `expires_at`, and file manifest. Progress goes to stderr.
Relative paths and content types are retained. A directory with `index.html`
gets an explicit entry-file URL; a single-file input gets that file's URL.
Directories without an entry file are collections, not browseable indexes:
link an individual file from their manifest. There is no SPA routing or server
execution. HTML is sandboxed: relative scripts, styles, images and module assets
work; application cookies, service workers, forms, embedded frames, and external
network dependencies are not supported.

Limits: 1,000 files per share, 100 MiB per file, 500 MiB per share, 20 share
reservations and 1 GiB reserved per user per UTC day, and 1,000 unexpired share
reservations per user. Failed reservations can count toward quotas. Shares
expire after 180 days; storage lifecycle cleanup is asynchronous. Hidden paths,
`node_modules`, `.pem`/`.key` files, and common private SSH keys are excluded.
Symlinks, special files, unsafe paths and non-UTF-8 filenames are rejected.
These exclusions are not a comprehensive secret scanner. Review the preview.

## Inspect, retry, and revoke

```sh
"$archdev" --json share show <share-id>
"$archdev" --json share complete <share-id>
"$archdev" --json share delete <share-id>
```

Only the uploader can inspect, complete, or delete a share. A share becomes
public only after every uploaded file matches the manifest and finalization
succeeds. `complete` safely retries finalization of an otherwise fully uploaded
share; it does not upload missing files. If finalization times out, inspect the
returned share ID before uploading again. Partial batch failures report already
completed shares: keep their URLs instead of duplicating those uploads.

A failed object upload attempts to delete its reservation. If cleanup failed,
retry `delete` with the reported ID. Deletion revokes the link and erases file
contents. Private zero-byte tombstones remain temporarily to prevent an
outstanding upload grant from recreating deleted files. Cached/downloaded
copies outside ArchDev cannot be revoked.

## Uploader attribution and administrative purge

Public URLs have `/u/<usr_ID>/<share_ID>/<relative-path>`; uploader identity is
also recorded server-side. All backing objects are scoped under the immutable
user ID. Anyone can identify the uploader ID from a URL without revealing their
email or allowing them to choose a different owner.

Only an operator-configured sharing administrator can run:

```sh
# Destructive: requires explicit user authorization for this target account.
"$archdev" --json share purge --user <usr_ID> --confirm
```

Purge disables future sharing for that user, immediately revokes their public
URLs, and erases all registered file payloads, including pending uploads. It
does not delete the ArchDev account or touch another uploader's files. Retry
an interrupted purge with the same user ID; completed cleanup is retained.
The persistent block remains until an operator deliberately clears it. Do not
purge an account merely to clean up one share; use `delete` instead.
