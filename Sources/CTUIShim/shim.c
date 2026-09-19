#include "include/ctui_shim.h"

#include <string.h>
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

int ctui_install_signal_handler(int signal_number,
                                void (*handler)(int),
                                struct sigaction *previous) {
    struct sigaction action;

    memset(&action, 0, sizeof(action));
    action.sa_handler = handler;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_NODEFER;
    return sigaction(signal_number, &action, previous);
}

int ctui_restore_signal_handler(int signal_number, const struct sigaction *previous) {
    return sigaction(signal_number, previous, 0);
}
