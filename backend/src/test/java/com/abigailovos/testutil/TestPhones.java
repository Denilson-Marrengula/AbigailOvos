package com.abigailovos.testutil;

import java.util.concurrent.atomic.AtomicLong;

/** Distinct synthetic Mozambique-format numbers for isolated tests. */
public final class TestPhones {
    private static final AtomicLong NEXT = new AtomicLong(820000000L);
    private TestPhones() {}
    public static String next() { return Long.toString(NEXT.getAndIncrement()); }
}
