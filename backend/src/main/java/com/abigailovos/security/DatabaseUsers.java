package com.abigailovos.security;

import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

@Service
class DatabaseUsers implements UserDetailsService {
    private final AppUserRepository users;

    DatabaseUsers(AppUserRepository users) {
        this.users = users;
    }

    @Override
    public UserDetails loadUserByUsername(String username) {
        AppUser user = users.findByUsername(username)
                .orElseThrow(() -> new UsernameNotFoundException("Utilizador não encontrado"));
        return User.withUsername(user.getUsername()).password(user.getPasswordHash())
                .roles(user.getRole()).disabled(!user.isEnabled()).build();
    }
}
