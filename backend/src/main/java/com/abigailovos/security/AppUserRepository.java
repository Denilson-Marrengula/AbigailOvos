package com.abigailovos.security;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;

interface AppUserRepository extends JpaRepository<AppUser, String> {
    Optional<AppUser> findByUsername(String username);
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select u from AppUser u where u.id = :id")
    Optional<AppUser> findForUpdate(@Param("id") String id);
}
