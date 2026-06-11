CC = gcc
CFLAGS = -Wall -Wextra -O2 -I src
LDFLAGS = -lyaml -lncurses
SRC_DIR = src
OBJ_DIR = obj
SRCS = $(wildcard $(SRC_DIR)/*.c)
OBJS = $(patsubst $(SRC_DIR)/%.c, $(OBJ_DIR)/%.o, $(SRCS))
TARGET = sshm

.PHONY: all clean dirs

all: dirs $(TARGET)

dirs:
	mkdir -p $(OBJ_DIR)

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c
	$(CC) $(CFLAGS) -c -o $@ $<

$(TARGET): $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS)

clean:
	rm -rf $(OBJ_DIR) $(TARGET)

install: $(TARGET)
	install -d $(DESTDIR)/usr/local/bin
	install -m 755 $(TARGET) $(DESTDIR)/usr/local/bin/sshm
	install -d $(DESTDIR)/usr/local/share/ssh-manager
	install -m 644 VERSION $(DESTDIR)/usr/local/share/ssh-manager/
	install -d $(DESTDIR)/usr/local/share/doc/ssh-manager
	install -m 644 README.md $(DESTDIR)/usr/local/share/doc/ssh-manager/ || true

uninstall:
	rm -f $(DESTDIR)/usr/local/bin/sshm
	rm -rf $(DESTDIR)/usr/local/share/ssh-manager

test: $(TARGET)
	@echo "Running tests..."
	@cd tests && bash -c 'echo "Tests TBD - see tests/ directory"'
