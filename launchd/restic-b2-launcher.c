/*
 * restic-b2-launcher: starts bin/backup and waits for it. Nothing else.
 *
 * Why it exists: macOS decides about access to files on an external drive per program,
 * and for a job started by launchd that program is the one launchd starts. If that is
 * /bin/bash, macOS refuses without asking, because bash is part of macOS. If it is this
 * program, macOS asks once ("restic-b2-launcher would like to access files on a
 * removable volume") and remembers the answer for this program alone. restic, started by
 * the script, is covered by the same answer. See README.md, "macOS privacy".
 *
 * It must stay the parent of the script. If it replaced itself with bash (exec), bash
 * would be the responsible program again.
 *
 * The script's absolute path is built in, so the permission can't be used to run
 * something else. The only argument passed on is --dry-run.
 *
 * Built by `bin/schedule install`, which passes the path:
 *   cc -O2 -Wall -Wextra -DSCRIPT='"/path/to/restic-b2-macos/bin/backup"' \
 *      -o launchd/restic-b2-launcher launchd/restic-b2-launcher.c
 * The result is git-ignored. macOS ties its permission to the built file: after a
 * rebuild from changed source, or for another path, it asks again.
 */

#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef SCRIPT
#error "build with -DSCRIPT='\"/absolute/path/to/bin/backup\"' (bin/schedule install does)"
#endif

#define SHELL "/bin/bash"

extern char **environ;

static volatile sig_atomic_t child = 0;

/* launchd stops a job with SIGTERM: hand it to the script, which then ends cleanly. */
static void pass_on(int sig) {
    if (child > 0) {
        kill((pid_t)child, sig);
    }
}

int main(int argc, char *argv[]) {
    char *args[] = {SHELL, SCRIPT, NULL, NULL};
    pid_t pid;
    int rc, status;

    if (argc == 2 && strcmp(argv[1], "--dry-run") == 0) {
        args[2] = argv[1];
    } else if (argc != 1) {
        fprintf(stderr, "usage: restic-b2-launcher [--dry-run]\n");
        return 2;
    }

    signal(SIGTERM, pass_on);
    signal(SIGHUP, pass_on);
    signal(SIGINT, pass_on);

    rc = posix_spawn(&pid, SHELL, NULL, NULL, args, environ);
    if (rc != 0) {
        fprintf(stderr, "restic-b2-launcher: can't start %s: %s\n", SHELL, strerror(rc));
        return 1;
    }
    child = pid;

    while (waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) {
            fprintf(stderr, "restic-b2-launcher: waitpid: %s\n", strerror(errno));
            return 1;
        }
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    return 128 + WTERMSIG(status);
}
