package com.fitloop.common;

import tools.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;

@Service
public class DomainEventOutbox {
    private final OutboxEventRepository events;
    private final ObjectMapper objectMapper;

    public DomainEventOutbox(OutboxEventRepository events, ObjectMapper objectMapper) {
        this.events = events;
        this.objectMapper = objectMapper;
    }

    public void append(String eventType, String aggregateId, Object payload) {
        try {
            OutboxEvent event = new OutboxEvent();
            event.setEventType(eventType);
            event.setAggregateId(aggregateId);
            event.setPayload(objectMapper.writeValueAsString(payload));
            events.save(event);
        } catch (Exception ex) {
            throw new IllegalStateException("Failed to persist domain event", ex);
        }
    }
}
