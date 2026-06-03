package com.fitloop.user;

import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doNothing;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fitloop.security.JwtAuthenticationFilter;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(AvatarController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestPropertySource(properties = "fitloop.upload.avatar-dir=target/test-uploads/avatars")
class AvatarControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private UserService userService;

    @MockBean
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    @BeforeEach
    void setUp() {
        SecurityContextHolder.getContext()
                .setAuthentication(new UsernamePasswordAuthenticationToken(1L, null, List.of()));
        doNothing().when(userService).updateAvatar(anyLong(), anyString());
    }

    @Test
    void rejectsEmptyFile() throws Exception {
        MockMultipartFile file = new MockMultipartFile(
                "file", "empty.jpg", "image/jpeg", new byte[0]);

        mockMvc.perform(multipart("/api/user/avatar").file(file))
                .andExpect(status().is4xxClientError())
                .andExpect(jsonPath("$.message").value("文件不能为空"));
    }

    @Test
    void rejectsFileExceeding5MB() throws Exception {
        byte[] largeContent = new byte[6 * 1024 * 1024]; // 6 MB
        MockMultipartFile file = new MockMultipartFile(
                "file", "large.jpg", "image/jpeg", largeContent);

        mockMvc.perform(multipart("/api/user/avatar").file(file))
                .andExpect(status().is4xxClientError())
                .andExpect(jsonPath("$.message").value("文件不能超过 5MB"));
    }

    @Test
    void acceptsValidJpegWithMagicBytes() throws Exception {
        // Valid JPEG header: FF D8 FF ...
        byte[] jpegBytes = new byte[]{
                (byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0,
                0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01
        };
        MockMultipartFile file = new MockMultipartFile(
                "file", "photo.jpg", "image/jpeg", jpegBytes);

        mockMvc.perform(multipart("/api/user/avatar").file(file))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0));
    }

    @Test
    void acceptsValidJpegWithNullContentType() throws Exception {
        // Simulates Android gallery where Content-Type may be null
        byte[] jpegBytes = new byte[]{
                (byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0,
                0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01
        };
        MockMultipartFile file = new MockMultipartFile(
                "file", "photo.jpg", null, jpegBytes);

        mockMvc.perform(multipart("/api/user/avatar").file(file))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0));
    }

    @Test
    void acceptsValidJpegWithApplicationOctetStream() throws Exception {
        // Some Android providers send application/octet-stream
        byte[] jpegBytes = new byte[]{
                (byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0,
                0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01
        };
        MockMultipartFile file = new MockMultipartFile(
                "file", "photo.jpg", "application/octet-stream", jpegBytes);

        mockMvc.perform(multipart("/api/user/avatar").file(file))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0));
    }

    @Test
    void acceptsValidJpegFileExtension() throws Exception {
        // .jpeg extension should be accepted
        byte[] jpegBytes = new byte[]{
                (byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0,
                0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01
        };
        MockMultipartFile file = new MockMultipartFile(
                "file", "photo.jpeg", "image/jpeg", jpegBytes);

        mockMvc.perform(multipart("/api/user/avatar").file(file))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0));
    }

    @Test
    void acceptsValidPngWithMagicBytes() throws Exception {
        // Valid PNG header: 89 50 4E 47 0D 0A 1A 0A
        byte[] pngBytes = new byte[]{
                (byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
        };
        MockMultipartFile file = new MockMultipartFile(
                "file", "icon.png", "image/png", pngBytes);

        mockMvc.perform(multipart("/api/user/avatar").file(file))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0));
    }

    @Test
    void rejectsTextFileEvenWithJpgExtension() throws Exception {
        // Text content disguised as .jpg
        byte[] textBytes = "This is not an image".getBytes();
        MockMultipartFile file = new MockMultipartFile(
                "file", "fake.jpg", "image/jpeg", textBytes);

        mockMvc.perform(multipart("/api/user/avatar").file(file))
                .andExpect(status().is4xxClientError())
                .andExpect(jsonPath("$.message").value("仅支持 JPG、JPEG、PNG 图片"));
    }

    @Test
    void rejectsPdfFile() throws Exception {
        // PDF header: %PDF
        byte[] pdfBytes = new byte[]{0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34};
        MockMultipartFile file = new MockMultipartFile(
                "file", "doc.pdf", "application/pdf", pdfBytes);

        mockMvc.perform(multipart("/api/user/avatar").file(file))
                .andExpect(status().is4xxClientError())
                .andExpect(jsonPath("$.message").value("仅支持 JPG、JPEG、PNG 图片"));
    }

    @Test
    void rejectsMismatchedContentType() throws Exception {
        // PNG magic bytes but claims to be image/jpeg
        byte[] pngBytes = new byte[]{
                (byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
        };
        MockMultipartFile file = new MockMultipartFile(
                "file", "icon.png", "image/jpeg", pngBytes);

        mockMvc.perform(multipart("/api/user/avatar").file(file))
                .andExpect(status().is4xxClientError())
                .andExpect(jsonPath("$.message").value("文件类型与扩展名不匹配，仅支持 JPG、JPEG、PNG 图片"));
    }
}
