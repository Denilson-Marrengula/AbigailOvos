package com.abigailovos.customer;

/** Canonical comparison key; this checks structure, not ownership or reachability. */
public final class CustomerPhone {
    private CustomerPhone() {}
    public static String canonical(String raw) { return CustomerPhoneV1.canonical(raw); }
}
