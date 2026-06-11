#include "yaml_parser.h"
#include "util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <yaml.h>

void node_init(node_t *n) {
    memset(n, 0, sizeof(node_t));
    n->port = 22;
    n->group = strdup("Default");
    n->type = strdup("pass");
    n->user = strdup("root");
}

void node_free(node_t *n) {
    if (!n) return;
    free(n->name);
    free(n->group);
    free(n->host);
    free(n->user);
    free(n->type);
    free(n->pass);
    free(n->keypath);
    free(n->tags);
    memset(n, 0, sizeof(node_t));
}

void node_list_init(node_list_t *list) {
    list->nodes = NULL;
    list->count = 0;
    list->capacity = 0;
}

void node_list_free(node_list_t *list) {
    if (!list) return;
    for (int i = 0; i < list->count; i++)
        node_free(&list->nodes[i]);
    free(list->nodes);
    list->nodes = NULL;
    list->count = 0;
    list->capacity = 0;
}

int node_list_add(node_list_t *list, const node_t *n) {
    if (list->count >= list->capacity) {
        int new_cap = list->capacity ? list->capacity * 2 : 16;
        node_t *new_nodes = realloc(list->nodes, new_cap * sizeof(node_t));
        if (!new_nodes) return -1;
        list->nodes = new_nodes;
        list->capacity = new_cap;
    }
    list->nodes[list->count] = *n;
    return list->count++;
}

static void node_finalize_defaults(node_t *n) {
    if (!n->group) n->group = strdup("Default");
    if (n->port <= 0) n->port = 22;
    if (!n->type) n->type = strdup("pass");
    if (!n->user) n->user = strdup("root");
    if (n->name) {
        char *t = str_trim(n->name);
        if (t != n->name) { free(n->name); n->name = strdup(t); }
    }
}

static int sort_by_group_name(const void *a, const void *b) {
    const node_t *na = (const node_t *)a;
    const node_t *nb = (const node_t *)b;
    int cmp = strcmp(na->group ? na->group : "", nb->group ? nb->group : "");
    if (cmp != 0) return cmp;
    return strcmp(na->name ? na->name : "", nb->name ? nb->name : "");
}

static int sort_by_name(const void *a, const void *b) {
    const node_t *na = (const node_t *)a;
    const node_t *nb = (const node_t *)b;
    return strcmp(na->name ? na->name : "", nb->name ? nb->name : "");
}

void node_list_sort(node_list_t *list, int sort_mode) {
    if (!list || list->count < 2) return;
    switch (sort_mode % 3) {
        case 0: qsort(list->nodes, list->count, sizeof(node_t), sort_by_group_name); break;
        case 1: qsort(list->nodes, list->count, sizeof(node_t), sort_by_name); break;
        case 2: break;
    }
}

static int parse_yaml_file(const char *path, node_list_t *list) {
    FILE *fh = fopen(path, "rb");
    if (!fh) return -1;

    yaml_parser_t parser;
    if (!yaml_parser_initialize(&parser)) {
        fclose(fh);
        return -1;
    }
    yaml_parser_set_input_file(&parser, fh);

    node_t current;
    memset(&current, 0, sizeof(current));
    int has_nodes_key = 0;
    int seq_depth = 0;
    int map_depth = 0;
    int in_node = 0;
    int expecting_val = 0;
    char *last_key = NULL;

    yaml_event_t event;
    while (yaml_parser_parse(&parser, &event)) {
        switch (event.type) {
            case YAML_SCALAR_EVENT: {
                const char *val = (const char *)event.data.scalar.value;
                if (!has_nodes_key && map_depth == 1 && seq_depth == 0 && strcmp(val, "nodes") == 0) {
                    has_nodes_key = 1;
                    expecting_val = 1;
                } else if (in_node && !expecting_val) {
                    free(last_key);
                    last_key = strdup(val);
                    expecting_val = 1;
                } else if (in_node && expecting_val && last_key) {
                    if (strcmp(last_key, "name") == 0) {
                        free(current.name);
                        current.name = strdup(val);
                    } else if (strcmp(last_key, "group") == 0) {
                        free(current.group);
                        current.group = strdup(val);
                    } else if (strcmp(last_key, "host") == 0) {
                        free(current.host);
                        current.host = strdup(val);
                    } else if (strcmp(last_key, "port") == 0) {
                        current.port = atoi(val);
                    } else if (strcmp(last_key, "user") == 0) {
                        free(current.user);
                        current.user = strdup(val);
                    } else if (strcmp(last_key, "type") == 0) {
                        free(current.type);
                        current.type = strdup(val);
                    } else if (strcmp(last_key, "pass") == 0) {
                        free(current.pass);
                        current.pass = strdup(val);
                    } else if (strcmp(last_key, "keypath") == 0) {
                        free(current.keypath);
                        current.keypath = strdup(val);
                    } else if (strcmp(last_key, "tags") == 0) {
                        free(current.tags);
                        current.tags = strdup(val);
                    }
                    free(last_key);
                    last_key = NULL;
                    expecting_val = 0;
                }
                break;
            }
            case YAML_MAPPING_START_EVENT: {
                map_depth++;
                if (has_nodes_key && seq_depth == 1 && map_depth == 2 && !in_node) {
                    memset(&current, 0, sizeof(current));
                    current.id = list->count + 1;
                    in_node = 1;
                    expecting_val = 0;
                }
                break;
            }
            case YAML_MAPPING_END_EVENT: {
                if (in_node && map_depth == 2) {
                    node_finalize_defaults(&current);
                    if (current.host && current.host[0] != '\0') {
                        node_list_add(list, &current);
                    } else {
                        node_free(&current);
                    }
                    memset(&current, 0, sizeof(current));
                    in_node = 0;
                    expecting_val = 0;
                }
                map_depth--;
                break;
            }
            case YAML_SEQUENCE_START_EVENT: {
                seq_depth++;
                break;
            }
            case YAML_SEQUENCE_END_EVENT: {
                seq_depth--;
                break;
            }
            default:
                break;
        }
        yaml_event_type_t etype = event.type;
        yaml_event_delete(&event);

        if (etype == YAML_STREAM_END_EVENT)
            break;
    }

    free(last_key);

    int ok = (parser.error == YAML_NO_ERROR);
    yaml_parser_delete(&parser);
    fclose(fh);

    if (!ok) {
        node_list_free(list);
        return -1;
    }
    return 0;
}

int read_node_info(const char *config_path, int id, node_t *node) {
    node_list_t list;
    node_list_init(&list);

    if (parse_yaml_file(config_path, &list) != 0) {
        node_init(node);
        return -1;
    }

    if (id < 1 || id > list.count) {
        node_init(node);
        node_list_free(&list);
        return -1;
    }

    *node = list.nodes[id - 1];
    memset(&list.nodes[id - 1], 0, sizeof(node_t));

    node_list_free(&list);
    return 0;
}

int get_all_nodes(const char *config_path, const char *filter_key, node_list_t *list) {
    node_list_init(list);
    if (parse_yaml_file(config_path, list) != 0)
        return -1;

    if (filter_key && filter_key[0] != '\0') {
        char name_filter[256] = "";
        char tag_filter[256] = "";

        /* Parse #tag tokens out of filter key */
        const char *p = filter_key;
        while (*p) {
            if (*p == '#') {
                p++;
                while (*p && *p != ' ') {
                    size_t len = strlen(tag_filter);
                    if (len < sizeof(tag_filter) - 2) {
                        tag_filter[len] = *p;
                        tag_filter[len + 1] = '\0';
                    }
                    p++;
                }
            } else {
                size_t len = strlen(name_filter);
                if (len < sizeof(name_filter) - 2) {
                    name_filter[len] = *p;
                    name_filter[len + 1] = '\0';
                }
                p++;
            }
        }

        char *trimmed = str_trim(name_filter);
        if (trimmed != name_filter)
            memmove(name_filter, trimmed, strlen(trimmed) + 1);

        node_list_t filtered;
        node_list_init(&filtered);

        for (int i = 0; i < list->count; i++) {
            node_t *n = &list->nodes[i];
            int match = 1;

            if (name_filter[0]) {
                int nm = 0;
                if (n->name && str_contains_ci(n->name, name_filter)) nm = 1;
                if (n->host && str_contains_ci(n->host, name_filter)) nm = 1;
                if (!nm) match = 0;
            }

            if (tag_filter[0] && match) {
                if (!n->tags || !str_contains_ci(n->tags, tag_filter))
                    match = 0;
            }

            if (match) {
                node_list_add(&filtered, n);
            } else {
                node_free(n);
            }
        }
        free(list->nodes);
        *list = filtered;
    }

    return list->count;
}
