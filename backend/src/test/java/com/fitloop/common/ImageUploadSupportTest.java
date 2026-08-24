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
    void acceptsDecodablePng() throws Exception {
        BufferedImage image = new BufferedImage(1, 1, BufferedImage.TYPE_INT_RGB);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(image, "png", out);
        assertThat(ImageUploadSupport.requireImage(out.toByteArray()))
                .isEqualTo(ImageUploadSupport.Format.PNG);
    }

    @Test
    void rejectsContentTypeMismatch() throws Exception {
        BufferedImage image = new BufferedImage(1, 1, BufferedImage.TYPE_INT_RGB);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(image, "png", out);
        assertThat(ImageUploadSupport.isCompatibleContentType("image/jpeg", ImageUploadSupport.Format.PNG))
                .isFalse();
        assertThat(ImageUploadSupport.isCompatibleContentType("image/png", ImageUploadSupport.Format.PNG))
                .isTrue();
    }
}
