package com.fitloop.architecture;

import static com.tngtech.archunit.library.dependencies.SlicesRuleDefinition.slices;

import com.tngtech.archunit.core.domain.JavaClasses;
import com.tngtech.archunit.core.importer.ClassFileImporter;
import com.tngtech.archunit.core.importer.ImportOption;
import org.junit.jupiter.api.Test;

class BusinessModuleArchitectureTest {

    @Test
    void businessModulesMustNotContainCycles() {
        JavaClasses modules = new ClassFileImporter()
                .withImportOption(ImportOption.Predefined.DO_NOT_INCLUDE_TESTS)
                .importPackages(
                "com.fitloop.sport",
                "com.fitloop.target",
                "com.fitloop.social",
                "com.fitloop.appeal",
                "com.fitloop.reminder",
                "com.fitloop.feedback");

        slices().matching("com.fitloop.(*)..")
                .should().beFreeOfCycles()
                .check(modules);
    }
}
