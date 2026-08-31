package com.fitloop.campus;

import com.fitloop.campus.CampusDtos.CampusLinkRequest;
import com.fitloop.campus.CampusDtos.CampusStatusResponse;
import jakarta.validation.Valid;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/internal/v1/campus")
public class CampusInternalController {
    private final CampusService campusService;
    private final byte[] serviceKey;

    public CampusInternalController(CampusService campusService,
                                    @Value("${fitloop.campus.service-key}") String serviceKey) {
        this.campusService = campusService;
        this.serviceKey = com.fitloop.security.ProductionSecrets.requireSecret(
                "fitloop.campus.service-key", serviceKey, 32);
    }

    @PostMapping("/link")
    public CampusStatusResponse link(@RequestHeader("X-Campus-Auth-Service-Key") String suppliedKey,
                                     @Valid @RequestBody CampusLinkRequest request) {
        if (!MessageDigest.isEqual(serviceKey, suppliedKey.getBytes(StandardCharsets.UTF_8))) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Invalid campus auth service credential");
        }
        return campusService.linkInternal(request);
    }
}
