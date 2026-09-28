// The slice of the system libsqlite3 API perchd uses, declared here instead of importing the SDK's
// SQLite3 module: a stray sqlite3.h in /usr/local/include (common after manual installs) makes
// `import SQLite3` fail with redefinition errors. Signatures match https://sqlite.org/c3ref/ .
#ifndef CSQLITE_H
#define CSQLITE_H

typedef struct sqlite3 sqlite3;
typedef struct sqlite3_stmt sqlite3_stmt;

#define SQLITE_OK 0
#define SQLITE_ROW 100
#define SQLITE_DONE 101
#define SQLITE_NULL 5
#define SQLITE_OPEN_READWRITE 0x00000002
#define SQLITE_OPEN_CREATE 0x00000004
#define SQLITE_OPEN_NOMUTEX 0x00008000

int sqlite3_open_v2(const char *filename, sqlite3 **db, int flags, const char *vfs);
int sqlite3_close_v2(sqlite3 *db);
const char *sqlite3_errmsg(sqlite3 *db);
int sqlite3_busy_timeout(sqlite3 *db, int ms);
int sqlite3_exec(sqlite3 *db, const char *sql, int (*callback)(void *, int, char **, char **), void *arg, char **errmsg);
void sqlite3_free(void *p);
int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int nbyte, sqlite3_stmt **stmt, const char **tail);
int sqlite3_finalize(sqlite3_stmt *stmt);
int sqlite3_bind_text(sqlite3_stmt *stmt, int index, const char *text, int nbyte, void (*destructor)(void *));
int sqlite3_bind_null(sqlite3_stmt *stmt, int index);
int sqlite3_bind_int64(sqlite3_stmt *stmt, int index, long long value);
int sqlite3_step(sqlite3_stmt *stmt);
int sqlite3_changes(sqlite3 *db);
int sqlite3_column_type(sqlite3_stmt *stmt, int column);
const unsigned char *sqlite3_column_text(sqlite3_stmt *stmt, int column);
long long sqlite3_column_int64(sqlite3_stmt *stmt, int column);

/// sqlite3_bind_text with SQLITE_TRANSIENT (sqlite copies the string).
static inline int csqlite_bind_text(sqlite3_stmt *stmt, int index, const char *text) {
    return sqlite3_bind_text(stmt, index, text, -1, (void (*)(void *))-1);
}

#endif
