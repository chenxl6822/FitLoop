package com.fitloop.user;

import com.fitloop.common.ApiResponse;
import com.fitloop.security.AuthSupport;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.Locale;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
public class AvatarController {

    private final UserService userService;
    private final Path uploadDir;

    public AvatarController(UserService userService,
                            @Value("${fitloop.upload.avatar-dir:uploads/avatars}") String avatarDir) {
        this.userService = userService;
        this.uploadDir = Paths.get(avatarDir).toAbsolutePath().normalize();
    }

    @PostMapping("/api/user/avatar")
    public ApiResponse<String> upload(@RequestParam("file") MultipartFile file) {
        if (file.isEmpty()) {
            throw new IllegalArgumentException("文件不能为空");
        }
        String contentType = file.getContentType();
        if (contentType == null || !contentType.startsWith("image/")) {
            throw new IllegalArgumentException("只能上传图片文件");
        }
        if (file.getSize() > 5 * 1024 * 1024) {
            throw new IllegalArgumentException("文件不能超过 5MB");
        }

        try {
            Files.createDirectories(uploadDir);

            String extension = extensionFor(contentType);
            String filename = UUID.randomUUID() + extension;
            Path targetPath = uploadDir.resolve(filename);

            Files.copy(file.getInputStream(), targetPath, StandardCopyOption.REPLACE_EXISTING);

            String avatarUrl = "/uploads/avatars/" + filename;
            userService.updateAvatar(AuthSupport.currentUserId(), avatarUrl);

            return ApiResponse.ok(avatarUrl);
        } catch (IOException e) {
            throw new IllegalArgumentException("文件上传失败: " + e.getMessage());
        }
    }

    private String extensionFor(String contentType) {
        return switch (contentType.toLowerCase(Locale.ROOT)) {
            case "image/jpeg", "image/jpg" -> ".jpg";
            case "image/png" -> ".png";
            case "image/gif" -> ".gif";
            case "image/webp" -> ".webp";
            default -> ".img";
        };
    }
}
