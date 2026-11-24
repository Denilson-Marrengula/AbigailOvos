package com.abigailovos.security;

import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import java.util.function.LongSupplier;

/** Per-process, per-connection-address limit; never trusts forwarded headers. */
final class BasicAttemptLimiter {
    private static final int MAX_FAILURES = 5;
    private static final long WINDOW = TimeUnit.MINUTES.toNanos(5);
    private static final int MAX_ADDRESSES = 10_000;
    private final LongSupplier clock;
    private final Map<String, Entry> entries = new HashMap<>();

    private static final class Entry {
        int failures;
        int inFlight;
        long firstFailure;
    }

    BasicAttemptLimiter() {
        this(System::nanoTime);
    }

    BasicAttemptLimiter(LongSupplier clock) {
        this.clock = clock;
    }

    /** Zero permits a request; positive values indicate Retry-After seconds. */
    synchronized long begin(String address) {
        long now = clock.getAsLong();
        Entry entry = entries.get(address);
        if (entry == null) {
            if (entries.size() >= MAX_ADDRESSES) cleanup(now);
            if (entries.size() >= MAX_ADDRESSES) return 60;
            entry = new Entry();
            entries.put(address, entry);
        }
        expire(entry, now);
        if (entry.failures >= MAX_FAILURES) {
            long remaining = WINDOW - (now - entry.firstFailure);
            return Math.max(1, (remaining + TimeUnit.SECONDS.toNanos(1) - 1) / TimeUnit.SECONDS.toNanos(1));
        }
        entry.inFlight++;
        return 0;
    }

    synchronized void finish(String address, boolean failed) {
        Entry entry = entries.get(address);
        if (entry == null) return;
        long now = clock.getAsLong();
        expire(entry, now);
        if (failed) {
            if (entry.failures == 0) entry.firstFailure = now;
            entry.failures++;
        }
        entry.inFlight--;
        if (entry.failures == 0 && entry.inFlight == 0) entries.remove(address);
    }

    private void cleanup(long now) {
        Iterator<Entry> iterator = entries.values().iterator();
        while (iterator.hasNext()) {
            Entry entry = iterator.next();
            expire(entry, now);
            if (entry.failures == 0 && entry.inFlight == 0) iterator.remove();
        }
    }

    private static void expire(Entry entry, long now) {
        if (entry.failures > 0 && now - entry.firstFailure >= WINDOW) entry.failures = 0;
    }
}
