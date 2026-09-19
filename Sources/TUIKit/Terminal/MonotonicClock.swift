#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// ある時点からの経過を表す単調増加の秒数。
func monotonicSeconds() -> Double {
    var time = timespec()
    clock_gettime(CLOCK_MONOTONIC, &time)
    return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
}
