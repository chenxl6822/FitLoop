package com.fitloop.sport;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;

import com.fitloop.common.DomainEventOutbox;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.mock.web.MockMultipartFile;
import tools.jackson.databind.ObjectMapper;

class SportPhotoSecurityTest {

    @TempDir
    Path photoDir;

    @Test
    void rejectsNonImageBytesEvenWhenClientClaimsImageMimeType() {
        SportService service = newSportService();
        var disguisedHtml = new MockMultipartFile(
                "file",
                "proof.png",
                "image/png",
                "<html><script>synthetic-proof</script></html>".getBytes(StandardCharsets.UTF_8));

        assertThatThrownBy(() -> service.savePhoto(9001L, disguisedHtml))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("图片");
    }

    @Test
    void acceptsDecodablePngAndIgnoresMisleadingExtension() throws Exception {
        SportService service = newSportService();
        BufferedImage image = new BufferedImage(1, 1, BufferedImage.TYPE_INT_RGB);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(image, "png", out);
        var png = new MockMultipartFile(
                "file",
                "proof.jpg",
                "image/png",
                out.toByteArray());

        assertThat(service.savePhoto(9001L, png)).endsWith(".png");
    }

    private SportService newSportService() {
        return new SportService(
                mock(SportRecordRepository.class),
                mock(SportTrackPointRepository.class),
                mock(IdempotencyRecordRepository.class),
                mock(CalorieCalculator.class),
                new ObjectMapper(),
                mock(ApplicationEventPublisher.class),
                mock(DomainEventOutbox.class),
                photoDir.toString());
    }
}
