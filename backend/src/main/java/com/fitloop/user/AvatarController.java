package com.fitloop.user;

import com.fitloop.common.ApiResponse;
import com.fitloop.security.AuthSupport;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.HexFormat;
import java.util.Locale;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
public class AvatarController {

    private static final long MAX_FILE_SIZE = 5 * 1024 * 1024;
    private static final byte[] JPEG_HEADER = {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF};
    private static final byte[] PNG_HEADER = {(byte) 0x89, 0x50, 0x4E, 0x47};

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
        if (file.getSize() > MAX_FILE_SIZE) {
            throw new IllegalArgumentException("文件不能超过 5MB");
        }

        String originalFilename = file.getOriginalFilename();
        String contentType = file.getContentType();

        try {
            // Read first 8 bytes for magic byte detection
            byte[] header = readHeader(file);

            // Determine image type from magic bytes first, then fall back to extension/content-type
            ImageType imageType = detectImageType(header, originalFilename, contentType);
            if (imageType == null) {
                throw new IllegalArgumentException("仅支持 JPG、JPEG、PNG 图片");
            }

            // Cross-validate: if content-type is present, it must be consistent with magic bytes
            if (contentType != null && !contentType.isBlank()) {
                if (!isCompatibleContentType(contentType, imageType)) {
                    throw new IllegalArgumentException("文件类型与扩展名不匹配，仅支持 JPG、JPEG、PNG 图片");
                }
            }

            Files.createDirectories(uploadDir);

            String extension = imageType.extension;
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

    private byte[] readHeader(MultipartFile file) throws IOException {
        byte[] header = new byte[8];
        try (InputStream in = file.getInputStream()) {
            int bytesRead = 0;
            int offset = 0;
            while (offset < header.length && (bytesRead = in.read(header, offset, header.length - offset)) != -1) {
                offset += bytesRead;
            }
        }
        return header;
    }

    private ImageType detectImageType(byte[] header, String originalFilename, String contentType) {
        // JPEG magic bytes: FF D8 FF
        if (header.length >= 3
                && header[0] == JPEG_HEADER[0]
                && header[1] == JPEG_HEADER[1]
                && header[2] == JPEG_HEADER[2]) {
            return ImageType.JPEG;
        }

        // PNG magic bytes: 89 50 4E 47
        if (header.length >= 4
                && header[0] == PNG_HEADER[0]
                && header[1] == PNG_HEADER[1]
                && header[2] == PNG_HEADER[2]
                && header[3] == PNG_HEADER[3]) {
            return ImageType.PNG;
        }

        // No valid image header detected — reject regardless of extension or content-type
        return null;
    }

    private boolean isCompatibleContentType(String contentType, ImageType imageType) {
        String lower = contentType.toLowerCase(Locale.ROOT);
        return switch (imageType) {
            case JPEG -> lower.equals("image/jpeg") || lower.equals("image/jpg")
                    || lower.equals("application/octet-stream") || lower.isEmpty();
            case PNG -> lower.equals("image/png")
                    || lower.equals("application/octet-stream") || lower.isEmpty();
        };
    }

    private enum ImageType {
        JPEG(".jpg"),
        PNG(".png");

        final String extension;

        ImageType(String extension) {
            this.extension = extension;
        }
    }
}
