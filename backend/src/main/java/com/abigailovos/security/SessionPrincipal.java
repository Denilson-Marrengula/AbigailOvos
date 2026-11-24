package com.abigailovos.security;

import java.security.Principal;

/** The HTTP context contains no password, session token or password hash. */
record SessionPrincipal(String username, boolean mustChangePassword) implements Principal {
    @Override public String getName() { return username; }
}
