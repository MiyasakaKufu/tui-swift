// glibc では posix_openpt などの宣言に必要。Darwin では既定で宣言されている。
#define _GNU_SOURCE 1

#include "include/ctui_test_support.h"

#include <fcntl.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <unistd.h>

int ctui_open_pty(int *master, int *slave) {
    int master_descriptor;
    int slave_descriptor;
    char *name;

    master_descriptor = posix_openpt(O_RDWR | O_NOCTTY);
    if (master_descriptor < 0) {
        return -1;
    }
    if (grantpt(master_descriptor) != 0 || unlockpt(master_descriptor) != 0) {
        close(master_descriptor);
        return -1;
    }
    name = ptsname(master_descriptor);
    if (name == 0) {
        close(master_descriptor);
        return -1;
    }
    slave_descriptor = open(name, O_RDWR | O_NOCTTY);
    if (slave_descriptor < 0) {
        close(master_descriptor);
        return -1;
    }

    *master = master_descriptor;
    *slave = slave_descriptor;
    return 0;
}

int ctui_set_terminal_size(int fd, int columns, int rows) {
    struct winsize ws;

    ws.ws_col = (unsigned short)columns;
    ws.ws_row = (unsigned short)rows;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;

    if (ioctl(fd, TIOCSWINSZ, &ws) != 0) {
        return -1;
    }
    return 0;
}
