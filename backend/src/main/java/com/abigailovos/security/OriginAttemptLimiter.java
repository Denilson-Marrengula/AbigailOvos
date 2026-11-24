package com.abigailovos.security;

import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import java.net.InetAddress;
import java.net.UnknownHostException;
import java.security.GeneralSecurityException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Arrays;
import java.util.Base64;
import java.util.HexFormat;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * Pre-authentication throttle for the unvalidated session-only mode. The caller must pass
 * a trustworthy numeric origin, never arbitrary X-Forwarded-For. At capacity it
 * fails closed; cleanup only removes old entries in this dedicated security table.
 * Proxy trust, the HMAC key and cluster behavior must be validated before use.
 */
@Service
class OriginAttemptLimiter {
    private static final String META_ID = "global";
    private static final Duration RETENTION = Duration.ofHours(1);
    private final EntityManager em;
    private final Clock clock;
    private final String configuredKey;
    private final int maxEntries;

    OriginAttemptLimiter(EntityManager em, Clock clock,
            @Value("${ABIGAIL_AUTH_ORIGIN_KEY:}") String configuredKey,
            @Value("${abigail.origin.max-entries:10000}") int maxEntries) {
        if (maxEntries < 1 || maxEntries > 100_000) throw new IllegalArgumentException("Limite de origens inválido.");
        this.em = em;
        this.clock = clock;
        this.configuredKey = configuredKey;
        this.maxEntries = maxEntries;
    }

    /** Uses an independent transaction so later rejected/failed logins cannot refund the charge. */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public boolean charge(String numericOrigin) {
        byte[] address = parseAddress(numericOrigin);
        if (address == null) return false;
        String hash = hash(address);
        OriginThrottleMeta meta = em.find(OriginThrottleMeta.class, META_ID, LockModeType.PESSIMISTIC_WRITE);
        if (meta == null) throw new IllegalStateException("Limite de origem indisponível.");
        em.refresh(meta, LockModeType.PESSIMISTIC_WRITE);
        Instant now = meta.observe(clock.instant());
        if (now == null) return false;
        OriginAttemptEntity origin = em.find(OriginAttemptEntity.class, hash, LockModeType.PESSIMISTIC_WRITE);
        if (origin != null) em.refresh(origin, LockModeType.PESSIMISTIC_WRITE);
        if (origin == null) {
            if (meta.entryCount() >= maxEntries && meta.mayPrune(now)) {
                int removed = em.createQuery("delete from OriginAttemptEntity o where o.lastRequestAt < :cutoff")
                        .setParameter("cutoff", now.minus(RETENTION)).executeUpdate();
                meta.pruned(now, removed);
            }
            if (meta.entryCount() >= maxEntries) return false;
            origin = new OriginAttemptEntity(hash, now);
            em.persist(origin);
            meta.added();
        }
        return origin.charge(now);
    }

    private String hash(byte[] address) {
        byte[] key = null;
        try {
            key = Base64.getDecoder().decode(configuredKey);
            if (key.length != 32 || !Base64.getEncoder().encodeToString(key).equals(configuredKey))
                throw new IllegalArgumentException();
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key, "HmacSHA256"));
            return HexFormat.of().formatHex(mac.doFinal(address));
        } catch (IllegalArgumentException | GeneralSecurityException error) {
            throw new IllegalStateException("Chave do limite de origem indisponível ou inválida.");
        } finally {
            Arrays.fill(address, (byte) 0);
            if (key != null) Arrays.fill(key, (byte) 0);
        }
    }

    private static byte[] parseAddress(String value) {
        if (value == null || value.length() > 45 || !value.matches("[0-9A-Fa-f:.]+")
                || (!value.contains(":") && !value.matches("[0-9]{1,3}(\\.[0-9]{1,3}){3}"))) return null;
        try {
            // The syntax check excludes hostnames and scoped addresses, avoiding DNS lookups.
            return InetAddress.getByName(value).getAddress();
        } catch (UnknownHostException error) {
            return null;
        }
    }
}
