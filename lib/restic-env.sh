# restic-env.sh: where restic-b2-macos keeps its settings and secrets, and how restic gets
# them. Sourced by the scripts in bin/, which set REPO (this repo's top folder) first.
# Never prints a secret.
#
# - The settings are in .env (see .env.example).
# - The B2 key and the repository password are in the login keychain, as generic passwords
#   under the service names below. bin/setup puts them there.
# - restic asks the keychain for the password itself (RESTIC_PASSWORD_COMMAND), so the
#   password is never in an environment variable or on a command line. The B2 key has to
#   be in restic's environment (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY), which only this
#   user and root can read.
#
# Messages in ENV_PROBLEM name no paths: they may end up in a push.
#
# Written for the bash 3.2 that macOS ships as /bin/bash.

# shellcheck shell=bash disable=SC2034  # ENV_PROBLEM and the KC_* names are read by the scripts that source this

readonly KC_PASSWORD=restic-b2-macos.restic-password
readonly KC_KEY_ID=restic-b2-macos.b2-key-id
readonly KC_KEY=restic-b2-macos.b2-key
KC_ACCOUNT=$(id -un)
readonly KC_ACCOUNT
readonly ENV_FILE=$REPO/.env
# s3:https://s3.<region>.backblazeb2.com/<bucket>
readonly REPOSITORY_RE='^s3:https://s3\.[a-z0-9-]+\.backblazeb2\.com/[A-Za-z0-9-]+$'

# Nothing from the caller's environment may choose another password or key.
unset RESTIC_PASSWORD RESTIC_PASSWORD_FILE RESTIC_PASSWORD_COMMAND RESTIC_REPOSITORY_FILE \
    AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE

ENV_PROBLEM=""   # why load_repository or load_secrets failed

# env_value NAME: the value of NAME in .env, without surrounding quotes. Empty if missing.
env_value() {
    if [[ -f $ENV_FILE ]]; then
        sed -n "s/^$1=//p" "$ENV_FILE" | tail -1 | sed -e "s/^'\(.*\)'\$/\1/" -e 's/^"\(.*\)"$/\1/'
    fi
}

kc_has()  { security find-generic-password -a "$KC_ACCOUNT" -s "$1" >/dev/null 2>&1; }
kc_read() { security find-generic-password -a "$KC_ACCOUNT" -s "$1" -w 2>/dev/null; }

# Sets and exports RESTIC_REPOSITORY. Returns 1, with the reason in ENV_PROBLEM, if .env
# doesn't give a usable address.
load_repository() {
    if [[ ! -f $ENV_FILE ]]; then
        ENV_PROBLEM=".env is missing (copy .env.example to .env and fill it in)"
        return 1
    fi
    RESTIC_REPOSITORY=$(env_value RESTIC_REPOSITORY)
    if [[ ! $RESTIC_REPOSITORY =~ $REPOSITORY_RE || $RESTIC_REPOSITORY == */change-me ]]; then
        ENV_PROBLEM="RESTIC_REPOSITORY in .env is not s3:https://s3.<region>.backblazeb2.com/<bucket>"
        return 1
    fi
    export RESTIC_REPOSITORY
}

# Exports what restic needs to open the repository. Returns 1, with the reason in
# ENV_PROBLEM, if something is missing from the keychain.
load_secrets() {
    local item
    for item in "$KC_KEY_ID" "$KC_KEY" "$KC_PASSWORD"; do
        if ! kc_has "$item"; then
            ENV_PROBLEM="keychain item $item is missing (run bin/setup)"
            return 1
        fi
    done
    if ! AWS_ACCESS_KEY_ID=$(kc_read "$KC_KEY_ID") || ! AWS_SECRET_ACCESS_KEY=$(kc_read "$KC_KEY"); then
        ENV_PROBLEM="the keychain won't hand out the B2 key (is the login keychain locked?)"
        return 1
    fi
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
    export RESTIC_PASSWORD_COMMAND="/usr/bin/security find-generic-password -a $KC_ACCOUNT -s $KC_PASSWORD -w"
}
