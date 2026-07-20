package com.fitloop.sport;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface SportTrackPointRepository extends JpaRepository<SportTrackPoint, Long> {
    List<SportTrackPoint> findByRecordIdOrderBySequenceNoAsc(Long recordId);

    Optional<SportTrackPoint> findTopByRecordIdOrderBySequenceNoDesc(Long recordId);

    @Query("select p.sequenceNo from SportTrackPoint p where p.recordId = :recordId "
            + "and p.sequenceNo in :sequenceNumbers")
    List<Integer> findExistingSequences(@Param("recordId") Long recordId,
                                        @Param("sequenceNumbers") Collection<Integer> sequenceNumbers);
}
