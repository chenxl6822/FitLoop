package com.fitloop.sport;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class CalorieCalculatorTest {
    private final CalorieCalculator calculator = new CalorieCalculator();

    @Test
    void estimatesCaloriesWithMetFormula() {
        double calories = calculator.estimate("running", 60, 1800);

        assertThat(calories).isEqualTo(240.0);
    }

    @Test
    void usesDefaultMetForCustomSports() {
        double calories = calculator.estimate("badminton", 60, 3600);

        assertThat(calories).isEqualTo(270.0);
    }
}
