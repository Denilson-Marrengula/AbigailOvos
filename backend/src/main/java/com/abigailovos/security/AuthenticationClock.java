package com.abigailovos.security;

import java.time.Clock;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
class AuthenticationClock {
    @Bean
    @ConditionalOnMissingBean(Clock.class)
    Clock authenticationSystemClock() { return Clock.systemUTC(); }
}
