package com.abigailovos.security;

import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.core.Ordered;

/** Registers the edge check before Spring Security, only for the Render profile. */
@Configuration
@Profile("render")
@ConditionalOnWebApplication(type = ConditionalOnWebApplication.Type.SERVLET)
class RenderEdgeConfiguration {
    @Bean
    FilterRegistrationBean<RenderEdgeFilter> renderEdgeFilterRegistration() {
        FilterRegistrationBean<RenderEdgeFilter> registration = new FilterRegistrationBean<>(new RenderEdgeFilter());
        registration.setName("renderEdgeFilter");
        registration.setOrder(Ordered.HIGHEST_PRECEDENCE + 10);
        registration.addUrlPatterns("/*");
        return registration;
    }
}
