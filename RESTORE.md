# Getting files back from the backup

Keep a copy of this with the **repository address** and the **password**: in your
password manager, and printed with the paper copy. The backup is in a Backblaze B2
bucket, encrypted with restic. Without the password it can't be read by anyone,
Backblaze included.

You need:
- the repository address and password (password manager or paper)
- a login to the Backblaze account (password and two-factor code)

## On the Mac that makes the backups

In this repository's folder:

```sh
bin/restic-b2 snapshots                        # the snapshots, newest last
bin/restic-b2 find 'IMG_2041*'                 # which snapshots hold a file
bin/restic-b2 restore latest \
    --include /Volumes/External/Photos/2024 --target ~/Desktop/restored
```

The files land under `~/Desktop/restored/Volumes/External/Photos/2024/…`, with their
dates.

- **Older version:** to get the version from an older snapshot, put its ID (first
  column of `snapshots`) in place of `latest`.
- **Everything:** leave out `--include`.

## On any other computer (the Mac is gone)

1. Install restic: `brew install restic` on a Mac, or see https://restic.net.
2. In the Backblaze web UI, under *Application Keys*, add a key:
   - *Bucket*: the one at the end of the repository address
   - *Type of access*: **Read Only**
   - Note the *keyID* and the *applicationKey*.
3. In a terminal (bash or zsh). The key is typed in at a prompt, not on a command line,
   so it stays out of the shell's history:

   ```sh
   printf 'keyID: '; read -r AWS_ACCESS_KEY_ID
   printf 'applicationKey (not shown): '; read -rs AWS_SECRET_ACCESS_KEY; echo
   export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
   export RESTIC_REPOSITORY='<repository address>'
   restic snapshots                              # asks for the password
   restic restore latest --target ~/restored     # everything; or add --include <folder>
   ```

   The download is about the size of the backed-up folders. B2 doesn't charge for
   downloads up to three times what is stored.
4. Afterwards, delete the read-only key in the web UI.

## When a file was deleted by mistake

- **From the Mac:** restore it from a snapshot from before the deletion. Daily snapshots
  go back a week, weekly ones five weeks, monthly ones two years, and yearly ones much
  longer.
- **From the backup itself:** files restic removed are only hidden at B2, for 30 days. In
  the web UI, *Browse Files*, "Show versions" shows them. Unhide them only if
  `restic check` reports missing data.
