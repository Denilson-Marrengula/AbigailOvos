package com.abigailovos.security;

import jakarta.persistence.EntityManager;
import org.springframework.stereotype.Repository;

/** Reservations are never removed, even when the corresponding seller is deleted. */
@Repository
class UsernameReservations {
    private final EntityManager em;
    UsernameReservations(EntityManager em) { this.em = em; }

    void reserve(AppUser user) {
        em.persist(new ReservedUsername(user));
        em.flush();
    }

    boolean belongsTo(AppUser user) {
        ReservedUsername reserved = em.find(ReservedUsername.class, ReservedUsername.key(user.getUsername()));
        return reserved != null && reserved.accountId().equals(user.getId());
    }
}
