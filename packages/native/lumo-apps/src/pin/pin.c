// SPDX-FileCopyrightText: 2026 Lumo contributors
// SPDX-License-Identifier: GPL-2.0-or-later

#define _GNU_SOURCE
#include <crypt.h>
#include <errno.h>
#include <fcntl.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define STORE "/var/lib/lumo/pin"
#define MIN_DIGITS 6
#define MAX_DIGITS 12
#define WIPE_AFTER 10

static int valid_pin(const char *pin)
{
    size_t length = strlen(pin);
    if (length < MIN_DIGITS || length > MAX_DIGITS) {
        return 0;
    }
    for (size_t i = 0; i < length; i++) {
        if (pin[i] < '0' || pin[i] > '9') {
            return 0;
        }
    }
    return 1;
}

static void read_token(char *buffer, size_t size)
{
    size_t used = 0;
    int c;
    while (used + 1 < size && (c = getchar()) != EOF && c != '\0' && c != '\n') {
        buffer[used++] = (char)c;
    }
    buffer[used] = '\0';
}

static void path_for(char *buffer, size_t size, uid_t uid, const char *suffix)
{
    snprintf(buffer, size, STORE "/%u%s", (unsigned)uid, suffix);
}

static long wait_for(int fails)
{
    if (fails >= 9) {
        return 1800;
    }
    if (fails >= 7) {
        return 300;
    }
    if (fails >= 5) {
        return 60;
    }
    return 0;
}

static int prepare_store(void)
{
    if (mkdir("/var/lib/lumo", 0755) != 0 && errno != EEXIST) {
        return -1;
    }
    if (mkdir(STORE, 0711) != 0 && errno != EEXIST) {
        return -1;
    }
    struct stat info;
    if (lstat(STORE, &info) != 0 || !S_ISDIR(info.st_mode) || info.st_uid != 0) {
        return -1;
    }
    chmod(STORE, 0711);
    return 0;
}

static int write_file(const char *path, const char *text)
{
    char temporary[256];
    snprintf(temporary, sizeof temporary, "%s.new", path);
    int fd = open(temporary, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) {
        return -1;
    }
    size_t length = strlen(text);
    int ok = write(fd, text, length) == (ssize_t)length && fsync(fd) == 0;
    close(fd);
    if (!ok || rename(temporary, path) != 0) {
        unlink(temporary);
        return -1;
    }
    return 0;
}

static int read_state(const char *path, int *fails, long *last)
{
    *fails = 0;
    *last = 0;
    FILE *file = fopen(path, "re");
    if (!file) {
        return 0;
    }
    if (fscanf(file, "%d %ld", fails, last) != 2) {
        *fails = 0;
        *last = 0;
    }
    fclose(file);
    return 0;
}

static int check(void)
{
    const char *type = getenv("PAM_TYPE");
    const char *service = getenv("PAM_SERVICE");
    const char *user = getenv("PAM_USER");
    if (!type || strcmp(type, "auth") != 0 || !service || !user) {
        return 1;
    }
    if (strcmp(service, "kde") != 0 && strcmp(service, "kde-fingerprint") != 0) {
        return 1;
    }
    struct passwd *entry = getpwnam(user);
    if (!entry) {
        return 1;
    }
    uid_t caller = getuid();
    if (caller != 0 && caller != entry->pw_uid) {
        return 1;
    }

    char token[64];
    read_token(token, sizeof token);
    if (!valid_pin(token)) {
        explicit_bzero(token, sizeof token);
        return 1;
    }

    char hash_path[256];
    char state_path[256];
    char lock_path[256];
    path_for(hash_path, sizeof hash_path, entry->pw_uid, "");
    path_for(state_path, sizeof state_path, entry->pw_uid, ".state");
    path_for(lock_path, sizeof lock_path, entry->pw_uid, ".lock");

    int lock = open(lock_path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (lock < 0 || flock(lock, LOCK_EX) != 0) {
        explicit_bzero(token, sizeof token);
        return 1;
    }

    char stored[256] = {0};
    FILE *file = fopen(hash_path, "re");
    if (!file || !fgets(stored, sizeof stored, file)) {
        if (file) {
            fclose(file);
        }
        explicit_bzero(token, sizeof token);
        return 1;
    }
    fclose(file);
    stored[strcspn(stored, "\n")] = '\0';

    int fails;
    long last;
    read_state(state_path, &fails, &last);
    long now = (long)time(NULL);
    if (now - last < wait_for(fails)) {
        explicit_bzero(token, sizeof token);
        return 1;
    }

    struct crypt_data data;
    memset(&data, 0, sizeof data);
    const char *hash = crypt_r(token, stored, &data);
    explicit_bzero(token, sizeof token);
    int match = hash && hash[0] != '*' && strcmp(hash, stored) == 0;
    explicit_bzero(&data, sizeof data);

    if (match) {
        unlink(state_path);
        return 0;
    }
    fails++;
    if (fails >= WIPE_AFTER) {
        unlink(hash_path);
        unlink(state_path);
        return 1;
    }
    char text[64];
    snprintf(text, sizeof text, "%d %ld\n", fails, now);
    write_file(state_path, text);
    return 1;
}

static uid_t requester(void)
{
    if (getuid() != 0) {
        return (uid_t)-1;
    }
    const char *value = getenv("PKEXEC_UID");
    if (!value || !*value) {
        return (uid_t)-1;
    }
    char *end = NULL;
    unsigned long uid = strtoul(value, &end, 10);
    if (*end != '\0' || !getpwuid((uid_t)uid)) {
        return (uid_t)-1;
    }
    return (uid_t)uid;
}

static int set(void)
{
    uid_t uid = requester();
    if (uid == (uid_t)-1 || prepare_store() != 0) {
        return 2;
    }
    char token[64];
    read_token(token, sizeof token);
    if (!valid_pin(token)) {
        explicit_bzero(token, sizeof token);
        return 3;
    }
    char salt[CRYPT_GENSALT_OUTPUT_SIZE];
    if (!crypt_gensalt_rn("$y$", 0, NULL, 0, salt, sizeof salt)) {
        explicit_bzero(token, sizeof token);
        return 2;
    }
    struct crypt_data data;
    memset(&data, 0, sizeof data);
    const char *hash = crypt_r(token, salt, &data);
    explicit_bzero(token, sizeof token);
    if (!hash || hash[0] == '*') {
        return 2;
    }
    char text[256];
    snprintf(text, sizeof text, "%s\n", hash);
    explicit_bzero(&data, sizeof data);
    char hash_path[256];
    char state_path[256];
    path_for(hash_path, sizeof hash_path, uid, "");
    path_for(state_path, sizeof state_path, uid, ".state");
    unlink(state_path);
    return write_file(hash_path, text) == 0 ? 0 : 2;
}

static int clear(void)
{
    uid_t uid = requester();
    if (uid == (uid_t)-1) {
        return 2;
    }
    char path[256];
    path_for(path, sizeof path, uid, "");
    unlink(path);
    path_for(path, sizeof path, uid, ".state");
    unlink(path);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: lumo-pin check|set|remove\n");
        return 2;
    }
    umask(077);
    if (strcmp(argv[1], "check") == 0) {
        return check();
    }
    if (strcmp(argv[1], "set") == 0) {
        return set();
    }
    if (strcmp(argv[1], "remove") == 0) {
        return clear();
    }
    return 2;
}
