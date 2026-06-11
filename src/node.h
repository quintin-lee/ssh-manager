#ifndef NODE_H
#define NODE_H

#include "yaml_parser.h"

char *sanitize_yaml_value(const char *val);

int add_node_interactive(void);
int edit_node_interactive(int id);
int delete_node_by_id(int id);
int undo_delete(void);
int import_from_ssh_config(const char *ssh_config_path);

#endif
