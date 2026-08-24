package com.fitloop.agent;

import com.fitloop.agent.AgentDtos.ProposalResponse;

/**
 * Raised when a run already has an action proposal. The response body carries the
 * stored proposal so callers can prove equivalence before treating the conflict as reuse.
 */
public class ExistingAgentProposalException extends RuntimeException {
    private final ProposalResponse existing;

    public ExistingAgentProposalException(ProposalResponse existing) {
        super("Agent run already has an action proposal");
        this.existing = existing;
    }

    public ProposalResponse existing() {
        return existing;
    }
}
