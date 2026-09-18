#include "include/ctui_shim.h"

#include <sys/ioctl.h>
#include <unistd.h>

int ctui_terminal_size(int fd, int *columns, int *rows) {
    struct winsize ws;

    if (ioctl(fd, TIOCGWINSZ, &ws) != 0) {
        return -1;
    }
    if (columns != 0) {
        *columns = (int)ws.ws_col;
    }
    if (rows != 0) {
        *rows = (int)ws.ws_row;
    }
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
