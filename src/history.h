#ifndef HISTORY_H
#define HISTORY_H

typedef struct {
    char *name;
    char *host;
    long timestamp;
} history_entry_t;

void history_record(const char *name, const char *host);
history_entry_t *history_get_recent(int *count);
void history_entry_free(history_entry_t *entry);

#endif
