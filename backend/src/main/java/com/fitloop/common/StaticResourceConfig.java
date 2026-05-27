package com.fitloop.common;

import java.nio.file.Path;
import java.nio.file.Paths;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class StaticResourceConfig implements WebMvcConfigurer {
    private final Path avatarDir;

    public StaticResourceConfig(@Value("${fitloop.upload.avatar-dir:uploads/avatars}") String avatarDir) {
        this.avatarDir = Paths.get(avatarDir).toAbsolutePath().normalize();
    }

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        String avatarLocation = avatarDir.toUri().toString();
        if (!avatarLocation.endsWith("/")) {
            avatarLocation += "/";
        }
        registry.addResourceHandler("/uploads/avatars/**")
                .addResourceLocations(avatarLocation);
    }
}
