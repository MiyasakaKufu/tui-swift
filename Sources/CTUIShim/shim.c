#include "include/ctui_shim.h"

#include <errno.h>
#include <stdlib.h>
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

/// クラッシュとして扱うシグナル。
///
/// Swift の `fatalError` や範囲外アクセスは、命令トラップとして SIGILL / SIGTRAP になる。
static const int ctui_crash_signal_numbers[] = {SIGILL, SIGTRAP, SIGABRT, SIGBUS, SIGSEGV};
enum { ctui_crash_signal_count = sizeof(ctui_crash_signal_numbers) / sizeof(ctui_crash_signal_numbers[0]) };

static volatile sig_atomic_t ctui_crash_is_armed = 0;
static volatile sig_atomic_t ctui_crash_input_descriptor = -1;
static volatile sig_atomic_t ctui_crash_output_descriptor = -1;
static struct termios ctui_crash_attributes;
static unsigned char *ctui_crash_sequence = 0;
static size_t ctui_crash_sequence_length = 0;
static struct sigaction ctui_crash_previous_actions[ctui_crash_signal_count];
static int ctui_crash_is_installed[ctui_crash_signal_count];
static int ctui_crash_is_handler_installed = 0;
static int ctui_crash_is_exit_handler_installed = 0;

static void ctui_write_all(int descriptor, const unsigned char *bytes, size_t count) {
    size_t offset = 0;
    while (offset < count) {
        ssize_t written = write(descriptor, bytes + offset, count - offset);
        if (written > 0) {
            offset += (size_t)written;
        } else if (written < 0 && errno == EINTR) {
            continue;
        } else {
            break;
        }
    }
}

void ctui_crash_restorer_restore(void) {
    if (ctui_crash_is_armed == 0) { return; }

    int output = (int)ctui_crash_output_descriptor;
    if (ctui_crash_sequence != 0 && output >= 0) {
        ctui_write_all(output, ctui_crash_sequence, ctui_crash_sequence_length);
    }
    int input = (int)ctui_crash_input_descriptor;
    if (input >= 0) {
        (void)tcsetattr(input, TCSAFLUSH, &ctui_crash_attributes);
    }
}

static void ctui_crash_restore_previous_action(int signal_number) {
    for (int index = 0; index < ctui_crash_signal_count; index++) {
        if (ctui_crash_signal_numbers[index] == signal_number && ctui_crash_is_installed[index]) {
            (void)sigaction(signal_number, &ctui_crash_previous_actions[index], 0);
            return;
        }
    }
}

static void ctui_crash_handle_signal(int signal_number) {
    ctui_crash_restorer_restore();

    // 前の設定へ戻さずに送り直してはいけない。`SA_NODEFER` のためこのハンドラがまた呼ばれ、
    // Swift ランタイムのクラッシュ表示やコアダンプが行われなくなる。
    ctui_crash_restore_previous_action(signal_number);
    (void)raise(signal_number);
}

static void ctui_crash_handle_exit(void) {
    ctui_crash_restorer_restore();
}

int ctui_crash_restorer_arm(int input,
                            int output,
                            const struct termios *attributes,
                            const unsigned char *sequence,
                            size_t length) {
    if (ctui_crash_sequence == 0) {
        unsigned char *buffer = malloc(length > 0 ? length : 1);
        if (buffer == 0) { return -1; }
        memcpy(buffer, sequence, length);
        ctui_crash_sequence_length = length;
        ctui_crash_sequence = buffer;
    }

    // 先に下ろすのをやめてはいけない。書き換えている途中でシグナルが来ると、ハンドラが
    // 古い記述子と新しい端末属性のような食い違った組で端末を戻す。
    ctui_crash_is_armed = 0;
    ctui_crash_input_descriptor = input;
    ctui_crash_output_descriptor = output;
    ctui_crash_attributes = *attributes;

    if (!ctui_crash_is_handler_installed) {
        for (int index = 0; index < ctui_crash_signal_count; index++) {
            ctui_crash_is_installed[index] =
                ctui_install_signal_handler(ctui_crash_signal_numbers[index],
                                            ctui_crash_handle_signal,
                                            &ctui_crash_previous_actions[index]) == 0;
        }
        ctui_crash_is_handler_installed = 1;
    }

    // このフラグを外すと、arm を呼ぶたびにハンドラが積まれる。
    // 終了時に同じ制御コードが、その回数だけ tty へ書き出される。
    if (!ctui_crash_is_exit_handler_installed) {
        ctui_crash_is_exit_handler_installed = 1;
        (void)atexit(ctui_crash_handle_exit);
    }

    ctui_crash_is_armed = 1;
    return 0;
}

void ctui_crash_restorer_disarm(void) {
    if (ctui_crash_is_armed == 0) { return; }
    ctui_crash_is_armed = 0;
    ctui_crash_input_descriptor = -1;
    ctui_crash_output_descriptor = -1;

    if (!ctui_crash_is_handler_installed) { return; }
    for (int index = 0; index < ctui_crash_signal_count; index++) {
        if (ctui_crash_is_installed[index]) {
            (void)ctui_restore_signal_handler(ctui_crash_signal_numbers[index],
                                              &ctui_crash_previous_actions[index]);
            ctui_crash_is_installed[index] = 0;
        }
    }
    ctui_crash_is_handler_installed = 0;
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
    // 書けなかったときに書き直してはいけない。書けないのはパイプが満杯のときで、読む側が止まって
    // いれば空かないので、シグナルハンドラから戻らなくなる。満杯なら起こす合図はすでに届いている。
    (void)write(descriptor, &byte, 1);
    errno = saved_errno;
}

void ctui_write_standard_error(const char *message) {
    fputs(message, stderr);
}
