package com.fitloop.campus;

import com.fitloop.campus.CampusDtos.CampusLinkRequest;
import com.fitloop.campus.CampusDtos.CampusStatusResponse;
import com.fitloop.campus.CampusDtos.CampusVerifyRequest;
import com.fitloop.user.UserInfo;
import com.fitloop.user.UserRepository;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Locale;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
public class CampusService {
    private final CampusVerificationRepository verifications;
    private final UserRepository users;
    private final CampusAuthClient campusAuthClient;
    private final CampusScheduleService campusScheduleService;
    private final byte[] idHashSecret;

    public CampusService(CampusVerificationRepository verifications,
                         UserRepository users,
                         CampusAuthClient campusAuthClient,
                         CampusScheduleService campusScheduleService,
                         @Value("${fitloop.campus.id-hash-secret}") String idHashSecret) {
        this.verifications = verifications;
        this.users = users;
        this.campusAuthClient = campusAuthClient;
        this.campusScheduleService = campusScheduleService;
        this.idHashSecret = com.fitloop.security.ProductionSecrets.requireSecret(
                "fitloop.campus.id-hash-secret", idHashSecret, 32);
    }

    public CampusStatusResponse status(Long userId) {
        return verifications.findByUserId(userId)
                .map(CampusStatusResponse::from)
                .orElseGet(CampusStatusResponse::unverified);
    }

    @Transactional
    public CampusStatusResponse verify(Long userId, CampusVerifyRequest request) {
        if (verifications.findByUserId(userId).isPresent()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Campus identity already linked");
        }
        var result = campusAuthClient.verify(
                userId,
                request.studentId().trim(),
                request.password());
        return linkInternal(new CampusLinkRequest(
                userId,
                hashStudentId(result.studentId()),
                result.college(),
                result.className(),
                result.major(),
                result.grade(),
                Instant.now(),
                "xtu_ems"));
    }

    @Transactional
    public CampusStatusResponse linkInternal(CampusLinkRequest request) {
        users.findById(request.userId())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "User not found"));
        if (verifications.findByUserId(request.userId()).isPresent()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Campus identity already linked");
        }
        verifications.findByStudentIdHash(request.studentIdHash()).ifPresent(existing -> {
            if (!existing.getUserId().equals(request.userId())) {
                throw new ResponseStatusException(HttpStatus.CONFLICT, "Student identity already linked");
            }
        });

        var verification = new CampusVerification();
        verification.setUserId(request.userId());
        verification.setStudentIdHash(request.studentIdHash());
        verification.setCollege(request.college());
        verification.setClassName(request.className());
        verification.setMajor(request.major());
        verification.setGrade(request.grade());
        verification.setVerifiedAt(request.verifiedAt() != null ? request.verifiedAt() : Instant.now());
        verification.setProvider(request.provider() != null ? request.provider() : "xtu_ems");
        var saved = verifications.save(verification);

        UserInfo user = users.findById(request.userId()).orElseThrow();
        user.setCollege(request.college());
        if (request.grade() != null && !request.grade().isBlank()) {
            user.setGrade(request.grade());
        }
        users.save(user);
        return CampusStatusResponse.from(saved);
    }

    @Transactional
    public void unlink(Long userId) {
        verifications.deleteByUserId(userId);
        campusScheduleService.deleteForUser(userId);
    }

    public String hashStudentId(String studentId) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(idHashSecret, "HmacSHA256"));
            byte[] digest = mac.doFinal(normalizeStudentId(studentId).getBytes(StandardCharsets.UTF_8));
            StringBuilder builder = new StringBuilder(digest.length * 2);
            for (byte value : digest) {
                builder.append(String.format(Locale.ROOT, "%02x", value));
            }
            return builder.toString();
        } catch (Exception ex) {
            throw new IllegalStateException("Unable to hash student id", ex);
        }
    }

    static String normalizeStudentId(String studentId) {
        return studentId.trim();
    }
}
