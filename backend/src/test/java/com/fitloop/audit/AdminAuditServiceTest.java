package com.fitloop.audit;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.context.annotation.Import;

@DataJpaTest
@Import(AdminAuditService.class)
class AdminAuditServiceTest {
    @Autowired
    private AdminAuditService audits;

    @Test
    void listsNewestAuditEntriesAndFiltersByResource() {
        audits.record(10L, "APPEAL_REVIEWED", "APPEAL", 1L, "{\"status\":\"approved\"}");
        audits.record(11L, "FEEDBACK_UPDATED", "FEEDBACK", 2L, "{\"status\":\"reviewed\"}");

        var all = audits.list(null, null, -1, 500);
        var filtered = audits.list("APPEAL", "1", 0, 20);

        assertThat(all.page()).isZero();
        assertThat(all.size()).isEqualTo(100);
        assertThat(all.totalElements()).isEqualTo(2);
        assertThat(filtered.items()).singleElement()
                .satisfies(entry -> {
                    assertThat(entry.actorUserId()).isEqualTo(10L);
                    assertThat(entry.action()).isEqualTo("APPEAL_REVIEWED");
                });
    }
}
