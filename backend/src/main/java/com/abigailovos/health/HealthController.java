package com.abigailovos.health;

import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** Static readiness response for the platform; no data or configuration is exposed. */
@RestController
public final class HealthController {
    @GetMapping(path = "/api/health", produces = MediaType.TEXT_PLAIN_VALUE)
    public ResponseEntity<String> health() {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body("ok");
    }
}
