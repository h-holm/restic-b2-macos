# restic-b2-macos

[![CI](https://github.com/h-holm/restic-b2-macos/actions/workflows/ci.yml/badge.svg)](https://github.com/h-holm/restic-b2-macos/actions/workflows/ci.yml)

A scheduled, encrypted offsite backup of folders on a Mac to Backblaze B2, built from
[restic](https://restic.net), launchd and the macOS keychain. It was written for a photo
library on an external drive. All of an installation's settings (folders, schedule,
bucket, notifications) live in one git-ignored file, `.env`.

`RESTORE.md` says how to get files back. Print it and keep it with the password.

## What it does

- **restic** keeps a repository of snapshots in a B2 bucket.
  - Each run uploads only what's new or changed.
  - A moved or renamed file costs nothing, because restic recognises content.
  - A day without changes takes seconds.
- **Every day**, at `SCHEDULE_TIME`, a LaunchAgent runs `bin/backup` on the folders in
  `BACKUP_PATHS`.
- **Once a week** the run also does maintenance:
  - `restic forget --prune` keeps 7 daily, 5 weekly, 24 monthly and 50 yearly snapshots,
    and frees what none of them needs.
  - `restic check --read-data-subset=5%` downloads 5% of the stored data and verifies it,
    a different 5% each time.
- **Pushes** go over [ntfy](https://ntfy.sh):
  - "*name* backup FAILED" (high priority) on any failure, with the reason.
  - "*name* backup OK" (low) after each maintenance, so about once a week.
  - Optionally, a [healthchecks.io](https://healthchecks.io) ping on every run. It emails
    you when runs stop happening at all, which no push can tell you.
- **Safety guard:** a run stops before backing anything up if any of these is true:
  - a backup folder's volume isn't mounted;
  - a folder is missing, empty or unreadable;
  - the folders hold fewer than `MIN_FILES` files between them.
- **Cost:**
  - B2 charges $6.95/TB/month (as of late 2026), and the first 10 GB are free.
  - Uploads are free. Downloads are free up to 3× the stored amount, which covers the
    checks and a full restore.
  - restic's deduplication keeps the repository close to the size of the folders.

## Privacy and threat model

- **Encrypted on the Mac:** restic encrypts every file's content, and also file names,
  folder names and dates, before anything leaves the Mac. It uses AES-256 with a
  Poly1305 integrity check, and the key is derived from the repository password.
- **What B2 stores:** blobs named by hashes (`data/3f/3fa9…`, `index/`, `snapshots/`,
  `keys/`, `config`). Whoever gets at the bucket gets ciphertext.
- **What B2 can see:** the total size, the size and time of each upload, and the Mac's IP
  address.
- **Secrets live in the login keychain,** put there by `bin/setup`:
  - the repository password, under service `restic-b2-macos.restic-password`
  - the B2 key, under `restic-b2-macos.b2-key-id` and `restic-b2-macos.b2-key`
- **Restic reads the password from the keychain itself.** It is never on a command line,
  in the environment, in `.env`, or in a log.
- **Pushes and pings** carry counts and sizes, never paths or names. The local log names
  the backup folders, and restic's messages there may name files.
- **The B2 key is restricted:**
  - It works for one bucket.
  - It can read, write and *hide* files, but not delete them for good (no `deleteFiles`)
    and not change the bucket (no `writeBuckets`).
  - Through B2's S3 API, restic's deletions only hide files, and the bucket's lifecycle
    rule deletes hidden files after 30 days.
  - So whoever takes over the Mac can't destroy the backup at once: there are 30 days to
    notice.
- **The repository password is the weak point.** Without it, the backup is lost for
  good; with it and the Backblaze login, anyone can read it. Keep two copies, at least
  one away from this Mac: in a password manager with end-to-end encryption, and on paper
  where you'd keep a passport. Keep no B2 keys with it, and the Backblaze 2FA in a
  separate authenticator app, so the password manager alone opens nothing.

## Files

| Path | What |
|---|---|
| `bin/backup` | the scheduled run (also `--dry-run`, `--maintenance`) |
| `bin/setup` | one-time setup of key, password and repository; run it yourself |
| `bin/restic-b2` | restic with this repository and its secrets: snapshots, restores, checks |
| `bin/schedule` | builds the launcher and installs, runs or removes the LaunchAgent |
| `lib/restic-env.sh` | where settings and secrets live; shared by the scripts |
| `launchd/` | the launcher's C source and the LaunchAgent template |
| `.env.example` | every setting, explained; copy to `.env` |
| `.github/workflows/ci.yml` | shellcheck, bash 3.2 syntax, the launcher and the LaunchAgent, on every push |

## Requirements

- macOS with [Homebrew](https://brew.sh), on Apple Silicon or Intel. Tested on macOS 15
  on Apple Silicon, with restic 0.20 and b2 5.0.
- The Xcode Command Line Tools (`xcode-select --install`), to build the launcher.
- A Backblaze B2 account with a payment method. Without one, B2 stops uploads at 10 GB.
- A logged-in user: the LaunchAgent runs only while you're logged in (a locked screen is
  fine).
- Optional: the [ntfy](https://ntfy.sh) app for pushes, and a
  [healthchecks.io](https://healthchecks.io) check. Without them, backups still run, but
  nothing tells you when one fails or stops.

## Setup

1. **B2, in the web UI** (backblaze.com):
   - Make an account in the region you want; it can't be changed later. Turn on
     two-factor authentication.
   - Add a payment method (*Billing*) and daily spending caps (*Caps & Alerts*).
   - Create a bucket: *Private*, with a random name that says nothing about its content.
   - In the bucket's *Lifecycle Settings*, choose "Keep prior versions for this number of
     days" and enter **30**.
   - The bucket page shows the *Endpoint*, e.g. `s3.eu-central-003.backblazeb2.com`.
   - Have the master application key at hand (*Application Keys*). If you generate a new
     one, the old one stops working.
2. **Tools:** `brew install restic b2-tools`
3. **Settings:** `cp .env.example .env && chmod 600 .env`, then fill in `.env`.
4. **Secrets and repository:** run `bin/setup` interactively in a terminal. It shows the
   password once, so run it where nothing records the screen. It does the following:
   - checks the bucket and creates the restricted key;
   - stores the key and the password in the keychain;
   - has you write the password down and type it back;
   - runs `restic init` and a self-test.
5. **Check:** `bin/backup --dry-run`
6. **First run**, from Terminal: `bin/backup`. It uploads everything once. That takes
   about 1.5 h per 30 GB at 50 Mbit/s upload, and 7 h at 10 Mbit/s. A progress line is
   logged once a minute.
7. **Restore test:**
   - Restore one folder: `bin/restic-b2 restore latest --include <a folder> --target ~/restore-test`
   - Compare it: `diff -r <a folder> ~/restore-test/<a folder>`, then delete
     `~/restore-test`. (Not `/tmp`: every user of the Mac can read files there.)
   - In the B2 web UI, browse the bucket: only hash names.
8. **Schedule:** see below.

## Schedule

```sh
bin/schedule show      # the LaunchAgent it would install
bin/schedule install   # build the launcher, install and load the LaunchAgent
bin/schedule run       # first run through launchd: be at the Mac
```

The first run through launchd makes macOS ask once: "restic-b2-launcher would like to
access files on a removable volume". Somebody has to be at the Mac to answer **Allow**.
Then check the log for `DONE`.

- **Changes:** after changing `SCHEDULE_TIME`, run `bin/schedule install` again.
- **Removal:** `bin/schedule remove` unloads the LaunchAgent and deletes it.

## macOS privacy

A job started by launchd gets the macOS permission of the program that launchd starts.
For `/bin/bash`, macOS refuses access to external drives without even asking, because
bash is part of macOS.

- **The launcher:** the job starts `launchd/restic-b2-launcher` instead. It is a short C
  program that runs `bin/backup` and waits. Because it isn't Apple's, macOS asks once.
  The permission then belongs to that program alone, covers external drives only, and
  also covers restic, which the script starts.
- **Built-in path:** the launcher's path to `bin/backup` is fixed when it's built, so the
  permission can't be used to run anything else.
- **Rejected alternative:** giving `/bin/bash` Full Disk Access would also work, but for
  every launchd job that runs a bash script, on the whole disk.
- **Managing it:** the permission can be switched off in System Settings → Privacy &
  Security → Files and Folders. After a rebuild from changed source, macOS asks again.
- **Seeing macOS's decision:**
  `/usr/bin/log show --last 10m --predicate 'process == "kernel" AND eventMessage CONTAINS "System Policy"'`
  (in zsh, plain `log` is a shell builtin).

## Day to day

- **Log:** `~/Library/Logs/restic-b2-macos.log`, with restic's output indented behind `|`.
- **Commands:**
  - `bin/restic-b2 snapshots`: what's in the backup.
  - `bin/restic-b2 stats --mode raw-data`: how much is stored.
  - `bin/backup --maintenance`: prune and check now.
  - `bin/restic-b2 check --read-data-subset=100%`: read back everything, once in a while.
- **More folders:** add them to `BACKUP_PATHS`, separated by `:`. Snapshots stay one
  series, and content that exists in several folders is stored once.
- **Yearly drill:** on another computer, with only the written-down address and password
  and `RESTORE.md`, list the snapshots and restore one file.

## When a run fails

The push says why, and the log has the details and restic's own message.

- **"a volume … is not mounted" / "a backup folder is missing … or macOS doesn't let
  this job read it"**: see "macOS privacy".
- **"can't open the repository"**: no network, or a key or password problem. Run
  `bin/restic-b2 snapshots` from Terminal to see restic's message.
- **"some files could not be read"**: the log names them. The other files are in the
  snapshot.
- **"unable to create lock" / "repository is already locked"**: after a run was killed,
  check that none is running (`pgrep -fl restic`), then run `bin/restic-b2 unlock`.
- **"restic check found a problem"**: don't prune or forget anything. Run
  `bin/restic-b2 check` for the details, then follow restic's documentation,
  "Troubleshooting".

## If the self-test fails

Backblaze doesn't document which key capability an S3 delete needs, so `bin/setup` tests
it. The native "hide" call needs `writeFiles`, which the key has. If restic still can't
remove files with the restricted key, backups would leave stale locks behind. Then:

1. In the web UI, delete the key `restic-b2-macos`.
2. Remove it from the keychain:
   `security delete-generic-password -s restic-b2-macos.b2-key-id`, and the same for
   `restic-b2-macos.b2-key`.
3. Add `deleteFiles` to `CAPABILITIES` in `bin/setup` and run it again.

restic's deletions still only hide files, and the lifecycle rule still keeps them for 30
days. But whoever takes over the Mac could then delete file versions for good.

## Development

- The scripts are written for the bash 3.2 that macOS ships as `/bin/bash`.
- After a change, run `shellcheck -x bin/* lib/*.sh` from the repository's top folder.
- Secrets (the repository password, the B2 keys, the ntfy topic, the healthchecks
  address) never go on a command line, where any process can read them, nor into the log
  or a push. `lib/restic-env.sh` reads them, and nothing prints them.
- Pushes and pings never carry paths or file names. `check_bad` in `bin/backup` takes a
  second, path-free message for the push.
- What differs per installation (folders, schedule, bucket, notifications) belongs in
  `.env`, and `.env.example` explains each setting. The backup policy is fixed in the
  scripts and described in this README: retention and the check share in `bin/backup`,
  the key's capabilities in `bin/setup`.
- CI (`.github/workflows/ci.yml`) runs shellcheck, checks the scripts against macOS's
  bash 3.2, builds the launcher and validates the rendered LaunchAgent.

## License

MIT; see `LICENSE`.
