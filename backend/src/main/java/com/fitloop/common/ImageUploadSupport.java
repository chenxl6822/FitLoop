package com.fitloop.common;

import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.Locale;
import javax.imageio.ImageIO;

/**
 * Validates uploaded image bytes by magic header and, where the JDK can decode,
 * by actually reading the raster. Client MIME / filename are never authoritative.
 */
public final class ImageUploadSupport {
    public enum Format {
        JPEG(".jpg", "image/jpeg"),
        PNG(".png", "image/png"),
        GIF(".gif", "image/gif"),
        WEBP(".webp", "image/webp");

        private final String extension;
        private final String mediaType;

        Format(String extension, String mediaType) {
            this.extension = extension;
            this.mediaType = mediaType;
        }

        public String extension() {
            return extension;
        }

        public String mediaType() {
            return mediaType;
        }
    }

    private ImageUploadSupport() {
    }

    public static Format requireImage(byte[] bytes) {
        if (bytes == null || bytes.length == 0) {
            throw new IllegalArgumentException("文件不能为空");
        }
        Format format = detectFormat(bytes);
        if (format == null) {
            throw new IllegalArgumentException("只能上传图片文件");
        }
        if (format != Format.WEBP) {
            requireDecodable(bytes);
        }
        return format;
    }

    public static boolean isCompatibleContentType(String contentType, Format format) {
        if (contentType == null || contentType.isBlank()) {
            return true;
        }
        String lower = contentType.toLowerCase(Locale.ROOT).trim();
        if (lower.equals("application/octet-stream")) {
            return true;
        }
        return switch (format) {
            case JPEG -> lower.equals("image/jpeg") || lower.equals("image/jpg");
            case PNG -> lower.equals("image/png");
            case GIF -> lower.equals("image/gif");
            case WEBP -> lower.equals("image/webp");
        };
    }

    static Format detectFormat(byte[] bytes) {
        if (bytes.length >= 3
                && (bytes[0] & 0xFF) == 0xFF
                && (bytes[1] & 0xFF) == 0xD8
                && (bytes[2] & 0xFF) == 0xFF) {
            return Format.JPEG;
        }
        if (bytes.length >= 8
                && (bytes[0] & 0xFF) == 0x89
                && bytes[1] == 0x50
                && bytes[2] == 0x4E
                && bytes[3] == 0x47
                && bytes[4] == 0x0D
                && bytes[5] == 0x0A
                && bytes[6] == 0x1A
                && bytes[7] == 0x0A) {
            return Format.PNG;
        }
        if (bytes.length >= 6
                && bytes[0] == 'G'
                && bytes[1] == 'I'
                && bytes[2] == 'F'
                && bytes[3] == '8'
                && (bytes[4] == '7' || bytes[4] == '9')
                && bytes[5] == 'a') {
            return Format.GIF;
        }
        if (bytes.length >= 12
                && bytes[0] == 'R'
                && bytes[1] == 'I'
                && bytes[2] == 'F'
                && bytes[3] == 'F'
                && bytes[8] == 'W'
                && bytes[9] == 'E'
                && bytes[10] == 'B'
                && bytes[11] == 'P') {
            return Format.WEBP;
        }
        return null;
    }

    private static void requireDecodable(byte[] bytes) {
        try {
            BufferedImage image = ImageIO.read(new ByteArrayInputStream(bytes));
            if (image == null || image.getWidth() <= 0 || image.getHeight() <= 0) {
                throw new IllegalArgumentException("只能上传图片文件");
            }
        } catch (IOException ex) {
            throw new IllegalArgumentException("只能上传图片文件");
        }
    }
}
