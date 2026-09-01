package com.fitloop.campus;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;

@Entity
@Table(name = "campus_schedule_course")
public class CampusScheduleCourse {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private Long userId;

    @Column(nullable = false, length = 128)
    private String courseName;

    @Column(length = 64)
    private String teacher;

    @Column(length = 128)
    private String classroom;

    @Column(nullable = false)
    private int dayOfWeek;

    @Column(nullable = false)
    private int startSection;

    @Column(nullable = false)
    private int sectionCount;

    @Column(length = 256)
    private String weeks;

    @Column(nullable = false, length = 16)
    private String termYear;

    @Column(nullable = false, length = 16)
    private String termCode;

    @Column(nullable = false)
    private Instant syncedAt;

    public Long getId() { return id; }
    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }
    public String getCourseName() { return courseName; }
    public void setCourseName(String courseName) { this.courseName = courseName; }
    public String getTeacher() { return teacher; }
    public void setTeacher(String teacher) { this.teacher = teacher; }
    public String getClassroom() { return classroom; }
    public void setClassroom(String classroom) { this.classroom = classroom; }
    public int getDayOfWeek() { return dayOfWeek; }
    public void setDayOfWeek(int dayOfWeek) { this.dayOfWeek = dayOfWeek; }
    public int getStartSection() { return startSection; }
    public void setStartSection(int startSection) { this.startSection = startSection; }
    public int getSectionCount() { return sectionCount; }
    public void setSectionCount(int sectionCount) { this.sectionCount = sectionCount; }
    public String getWeeks() { return weeks; }
    public void setWeeks(String weeks) { this.weeks = weeks; }
    public String getTermYear() { return termYear; }
    public void setTermYear(String termYear) { this.termYear = termYear; }
    public String getTermCode() { return termCode; }
    public void setTermCode(String termCode) { this.termCode = termCode; }
    public Instant getSyncedAt() { return syncedAt; }
    public void setSyncedAt(Instant syncedAt) { this.syncedAt = syncedAt; }
}
