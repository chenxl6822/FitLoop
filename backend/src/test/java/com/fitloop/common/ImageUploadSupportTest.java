package com.fitloop.common;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.Test;

class ImageUploadSupportTest {

    @Test
    void rejectsHtmlDisguisedAsPng() {
        assertThatThrownBy(() -> ImageUploadSupport.requireImage(
                        "<html>nope</html>".getBytes()))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("图片");
    }

    @Test
    void rejectsNullOrEmptyBytes() {
        assertThatThrownBy(() -> ImageUploadSupport.requireImage(null))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("空");
        assertThatThrownBy(() -> ImageUploadSupport.requireImage(new byte[0]))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("空");
    }

    @Test
    void acceptsDecodableFormatsAndWebpMagic() throws Exception {
        assertThat(ImageUploadSupport.requireImage(encode("png")))
                .isEqualTo(ImageUploadSupport.Format.PNG);
        assertThat(ImageUploadSupport.requireImage(encode("jpg")))
                .isEqualTo(ImageUploadSupport.Format.JPEG);
        assertThat(ImageUploadSupport.requireImage(encode("gif")))
                .isEqualTo(ImageUploadSupport.Format.GIF);
        assertThat(ImageUploadSupport.requireImage(sampleWebp()))
                .isEqualTo(ImageUploadSupport.Format.WEBP);
        assertThat(ImageUploadSupport.requireImage(sampleGif87a()))
                .isEqualTo(ImageUploadSupport.Format.GIF);
    }

    @Test
    void rejectsUndecodableJpegMagic() {
        assertThatThrownBy(() -> ImageUploadSupport.requireImage(
                        new byte[]{(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, 0x00}))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("图片");
    }

    @Test
    void contentTypeCompatibilityCoversAllFormats() {
        assertThat(ImageUploadSupport.isCompatibleContentType(null, ImageUploadSupport.Format.PNG)).isTrue();
        assertThat(ImageUploadSupport.isCompatibleContentType("  ", ImageUploadSupport.Format.JPEG)).isTrue();
        assertThat(ImageUploadSupport.isCompatibleContentType("application/octet-stream",
                ImageUploadSupport.Format.WEBP)).isTrue();
        assertThat(ImageUploadSupport.isCompatibleContentType("image/jpeg", ImageUploadSupport.Format.JPEG)).isTrue();
        assertThat(ImageUploadSupport.isCompatibleContentType("image/jpg", ImageUploadSupport.Format.JPEG)).isTrue();
        assertThat(ImageUploadSupport.isCompatibleContentType("image/png", ImageUploadSupport.Format.PNG)).isTrue();
        assertThat(ImageUploadSupport.isCompatibleContentType("image/gif", ImageUploadSupport.Format.GIF)).isTrue();
        assertThat(ImageUploadSupport.isCompatibleContentType("image/webp", ImageUploadSupport.Format.WEBP)).isTrue();
        assertThat(ImageUploadSupport.isCompatibleContentType("image/jpeg", ImageUploadSupport.Format.PNG)).isFalse();
        assertThat(ImageUploadSupport.isCompatibleContentType("image/png", ImageUploadSupport.Format.GIF)).isFalse();
        assertThat(ImageUploadSupport.Format.JPEG.extension()).isEqualTo(".jpg");
        assertThat(ImageUploadSupport.Format.PNG.mediaType()).isEqualTo("image/png");
    }

    private static byte[] encode(String format) throws Exception {
        BufferedImage image = new BufferedImage(1, 1, BufferedImage.TYPE_INT_RGB);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(image, format, out);
        return out.toByteArray();
    }

    private static byte[] sampleWebp() {
        return new byte[] {
                'R', 'I', 'F', 'F', 0x1A, 0x00, 0x00, 0x00,
                'W', 'E', 'B', 'P',
                'V', 'P', '8', ' ', 0x0E, 0x00, 0x00, 0x00,
                0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E
        };
    }

    private static byte[] sampleGif87a() throws Exception {
        // ImageIO may emit GIF89a; keep an explicit GIF87a magic for branch coverage.
        byte[] gif = encode("gif");
        gif[4] = '7';
        return gif;
    }
}
