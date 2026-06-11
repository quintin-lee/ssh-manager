#ifndef YAML_PARSER_H
#define YAML_PARSER_H

typedef struct {
    int id;
    char *name;
    char *group;
    char *host;
    int port;
    char *user;
    char *type;
    char *pass;
    char *keypath;
    char *tags;
} node_t;

typedef struct {
    node_t *nodes;
    int count;
    int capacity;
} node_list_t;

void node_init(node_t *n);
void node_free(node_t *n);
void node_list_init(node_list_t *list);
void node_list_free(node_list_t *list);
int node_list_add(node_list_t *list, const node_t *n);

int read_node_info(const char *config_path, int id, node_t *node);
int get_all_nodes(const char *config_path, const char *filter_key, node_list_t *list);
void node_list_sort(node_list_t *list, int sort_mode);

#endif
