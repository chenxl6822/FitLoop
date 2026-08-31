package com.fitloop.campus;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;

@Entity
@Table(name = "campus_verification")
public class CampusVerification {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false, unique = true)
    private Long userId;

    @Column(name = "student_id_hash", nullable = false, unique = true, length = 64)
    private String studentIdHash;

    @Column(nullable = false, length = 128)
    private String college;

    @Column(name = "class_name", nullable = false, length = 128)
    private String className;

    @Column(length = 128)
    private String major;

    @Column(length = 64)
    private String grade;

    @Column(name = "verified_at", nullable = false)
    private Instant verifiedAt;

    @Column(nullable = false, length = 32)
    private String provider = "xtu_ems";

    public Long getId() { return id; }

    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }

    public String getStudentIdHash() { return studentIdHash; }
    public void setStudentIdHash(String studentIdHash) { this.studentIdHash = studentIdHash; }

    public String getCollege() { return college; }
    public void setCollege(String college) { this.college = college; }

    public String getClassName() { return className; }
    public void setClassName(String className) { this.className = className; }

    public String getMajor() { return major; }
    public void setMajor(String major) { this.major = major; }

    public String getGrade() { return grade; }
    public void setGrade(String grade) { this.grade = grade; }

    public Instant getVerifiedAt() { return verifiedAt; }
    public void setVerifiedAt(Instant verifiedAt) { this.verifiedAt = verifiedAt; }

    public String getProvider() { return provider; }
    public void setProvider(String provider) { this.provider = provider; }
}
