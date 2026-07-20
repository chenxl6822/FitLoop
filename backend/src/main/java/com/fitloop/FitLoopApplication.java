package com.fitloop;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class FitLoopApplication {
    public static void main(String[] args) {
        SpringApplication.run(FitLoopApplication.class, args);
    }
}
