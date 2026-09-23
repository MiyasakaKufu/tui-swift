#include "include/ctui_shim.h"

#include <errno.h>
#include <string.h>
#include <stdio.h>
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

static volatile sig_atomic_t ctui_window_resize_flag = 0;
static volatile sig_atomic_t ctui_termination_flag = 0;
static volatile sig_atomic_t ctui_suspend_flag = 0;
static volatile sig_atomic_t ctui_continue_flag = 0;
static volatile sig_atomic_t ctui_wakeup_read_descriptor = -1;
static volatile sig_atomic_t ctui_wakeup_write_descriptor = -1;

void ctui_signal_set_window_resize(void) { ctui_window_resize_flag = 1; }
void ctui_signal_set_termination(void) { ctui_termination_flag = 1; }
void ctui_signal_set_suspend(void) { ctui_suspend_flag = 1; }
void ctui_signal_set_continue(void) { ctui_continue_flag = 1; }

static int ctui_consume(volatile sig_atomic_t *flag) {
    if (*flag == 0) { return 0; }
    *flag = 0;
    return 1;
}

int ctui_signal_consume_window_resize(void) { return ctui_consume(&ctui_window_resize_flag); }
int ctui_signal_consume_termination(void) { return ctui_consume(&ctui_termination_flag); }
int ctui_signal_consume_suspend(void) { return ctui_consume(&ctui_suspend_flag); }
int ctui_signal_consume_continue(void) { return ctui_consume(&ctui_continue_flag); }

void ctui_signal_set_wakeup_pipe(int read_end, int write_end) {
    ctui_wakeup_read_descriptor = read_end;
    ctui_wakeup_write_descriptor = write_end;
}

int ctui_signal_wakeup_read_descriptor(void) { return (int)ctui_wakeup_read_descriptor; }

void ctui_signal_wake_up(void) {
    int descriptor = (int)ctui_wakeup_write_descriptor;
    if (descriptor < 0) { return; }

    // `errno` の退避を外してはいけない。割り込まれた側が、自分が呼んだ関数の `errno` を
    // 読んだつもりで `write(2)` の結果を読む。
    int saved_errno = errno;
    unsigned char byte = 0;
    // 書けなくても書き直さない。起こす合図は 1 バイトあれば足りる。
    (void)write(descriptor, &byte, 1);
    errno = saved_errno;
}

void ctui_write_standard_error(const char *message) {
    fputs(message, stderr);
}
