#include "include/ctui_test_support.h"

#include <fcntl.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <unistd.h>

int ctui_test_open_pty(int *master, int *slave) {
    int master_fd = posix_openpt(O_RDWR | O_NOCTTY);
    if (master_fd < 0) {
        return -1;
    }
    if (grantpt(master_fd) != 0 || unlockpt(master_fd) != 0) {
        close(master_fd);
        return -1;
    }

    const char *name = ptsname(master_fd);
    if (name == 0) {
        close(master_fd);
        return -1;
    }

    int slave_fd = open(name, O_RDWR | O_NOCTTY);
    if (slave_fd < 0) {
        close(master_fd);
        return -1;
    }

    *master = master_fd;
    *slave = slave_fd;
    return 0;
}

int ctui_test_set_terminal_size(int fd, int columns, int rows) {
    struct winsize ws;

    ws.ws_col = (unsigned short)columns;
    ws.ws_row = (unsigned short)rows;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;

    return ioctl(fd, TIOCSWINSZ, &ws) == 0 ? 0 : -1;
}
