#ifndef CONFIG_H
#define CONFIG_H

#include <time.h>

extern char *g_config_path;
extern time_t g_config_mtime;

int config_resolve(void);
int config_setup_permissions(void);
int config_backup(void);
int config_update_mtime(void);

#endif
