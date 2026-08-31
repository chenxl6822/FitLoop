package com.fitloop.campus;

import jakarta.validation.constraints.NotBlank;
import java.time.Instant;

public final class CampusDtos {
    private CampusDtos() {
    }

    public record CampusStatusResponse(
            boolean verified,
            String college,
            String className,
            String major,
            String grade,
            Instant verifiedAt
    ) {
        public static CampusStatusResponse unverified() {
            return new CampusStatusResponse(false, null, null, null, null, null);
        }

        public static CampusStatusResponse from(CampusVerification verification) {
            return new CampusStatusResponse(
                    true,
                    verification.getCollege(),
                    verification.getClassName(),
                    verification.getMajor(),
                    verification.getGrade(),
                    verification.getVerifiedAt()
            );
        }
    }

    public record CampusVerifyRequest(@NotBlank String studentId, @NotBlank String password) {
    }

    public record CampusLinkRequest(
            Long userId,
            @NotBlank String studentIdHash,
            @NotBlank String college,
            @NotBlank String className,
            String major,
            String grade,
            Instant verifiedAt,
            String provider
    ) {
    }
}
